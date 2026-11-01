SplitErrors := choice_union#(
    .a : BuildErrors,
    .b : (
        ..missing_vertex,
        ..unsupported_boundary,
        ..invalid_parameter,
        ..endpoint_not_on_boundary,
        ..degenerate_cut,
        ..cut_outside_face
    )
)

-- One-to-many history borrows only the original domain. The output owns its
-- geometry and connectivity and can be moved out independently of that history.
FaceSplit := #(.Scalar: Type: Float) (
    .model        : Model#(Scalar),
    .cut_edge     : EdgeId,
    .cut_start    : VertexId,
    .cut_end      : VertexId,
    .faces        : [2]FaceId,
    ._source      : &idx.IndexDomain,
    ._vertices    : UIntNative,
    ._edges       : UIntNative,
    ._face_count  : UIntNative,
    ._split_edges : [2] ?EdgeId,
    ._edge_parts  : [2]EdgeId
)

_SplitConnectivity := (
    .halfedges : DynamicArray#(HalfEdge),
    .loops     : DynamicArray#(Loop),
    .faces     : DynamicArray#(Face),
    .surfaces  : DynamicArray#(SurfaceId)
)

_split_emit_loop := (
    .destination : $&_SplitConnectivity,
    .uses        : &DynamicArray#(_BoundaryUse),
    .range       : _BoundaryRange,
    .offset      : UIntNative,
    .count       : UIntNative,
    .chord       : ?_BoundaryUse,
    .allocator   : $&Virtual#(Allocator)
) -> (.result: Errable#(Void, SplitErrors)) {

    first ::= length(&destination&.halfedges).count
    loop_index ::= length(&destination&.loops).count
    loop_id ::= loop_index | convert#(.to: LoopId)(_)
    total ::= count
    match chord { ..none {} ..some _ { total = total + 1 } }
    cursor ::= offset
    i :: UIntNative = 0
    while i < total {
        item :: _BoundaryUse = (.origin = ..none, .edge = (.value = 0), .reversed = false)
        if i < count {
            item = get(uses, .index = range.start + cursor)!
            cursor = cursor + 1
            if cursor == range.count { cursor = 0 }
        } else {
            match chord { ..none { abort } ..some use { item = use.value } }
        }
        halfedge: HalfEdge = (
            .origin   = item.origin
            .edge     = item.edge
            .next     = [[[first + [i + 1] % total] | convert#(.to: HalfEdgeId)(_)]]
            .loop     = loop_id
            .reversed = item.reversed
            .pcurve   = item.pcurve
        )
        push($&destination&.halfedges, .value = halfedge, .allocator = allocator)!
        i = i + 1
    }
    boundary: Loop = (
        .first = [first | convert#(.to: HalfEdgeId)(_)]
        .count = total
    )
    push($&destination&.loops, .value = boundary, .allocator = allocator)!
    result = ..ok Void()
}

split_planar_face := #(.Scalar: Type: Float) (
    .model     : &Model#(Scalar),
    .face      : FaceId,
    .start     : BoundaryPoint#(Scalar),
    .end       : BoundaryPoint#(Scalar),
    .allocator : $&Virtual#(Allocator)
) -> (.result: Errable#(FaceSplit#(Scalar), SplitErrors)) {

    original ::= face_info(model, .face = face)!
    plane ::= face_plane(model, .face = face)!
    if original.loop_count == 0 or original.genus != 0 {
        result = ..error(.reason = ..unsupported_boundary)
        return
    }
    -- All selected segments must be linear. Unrelated analytic faces and closed
    -- curves are carried through without forcing them into polygon constructors.
    _require_linear_planar_boundaries(.model = model, .face = face)!
    counts ::= entity_counts(model)
    maximum ::= integer_limits(.value = counts.halfedges).maximum
    if [
        counts.halfedges > maximum - 6
        or counts.vertices > maximum - 2
        or counts.edges > maximum - 3
        or counts.faces == maximum
        or counts.loops == maximum
    ] {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    next_vertex ::= counts.vertices | convert#(.to: VertexId)(_)
    a ::= _split_endpoint(
        .model      = model
        .loop       = original.first_loop
        .location   = start
        .new_vertex = next_vertex
    )!
    added :: UIntNative = 0
    if a.insert { added = 1 }
    next_vertex = [[[counts.vertices + added] | convert#(.to: VertexId)(_)]]
    b ::= _split_endpoint(
        .model = model, .loop = original.first_loop, .location = end, .new_vertex = next_vertex
    )!
    if a.vertex == b.vertex or a.edge == b.edge {
        result = ..error(.reason = ..degenerate_cut)
        return
    }
    length ::= g.norm(.vector = g.between(.from = a.point, .to = b.point).result).value
    if is_finite(length).ok == false {
        result = ..error(.reason = ..numeric_range)
        return
    }
    if length <= model&._validation_tolerance {
        result = ..error(.reason = ..degenerate_cut)
        return
    }
    part_a ::= counts.edges | convert#(.to: EdgeId)(_)
    part_b ::= [counts.edges + added] | convert#(.to: EdgeId)(_)
    if b.insert { added = added + 1 }
    cut ::= [counts.edges + added] | convert#(.to: EdgeId)(_)
    parts: [2]EdgeId = (part_a, part_b)
    boundary ::= _split_refine(
        .model = model, .first = a, .second = b, .parts = parts, .allocator = allocator
    )!
    loop_index ::= original.first_loop | convert#(.to: UIntNative)(_)
    range ::= get(&boundary.loops, .index = loop_index)!
    distance :: UIntNative = 0
    if boundary.second >= boundary.first {
        distance = boundary.second - boundary.first
    } else {
        distance = range.count - boundary.first + boundary.second
    }
    if distance < 2 or range.count - distance < 2 {
        result = ..error(.reason = ..degenerate_cut)
        return
    }
    points ::= copy(&model&._points, .allocator = allocator)!
    if a.insert { push($&points, .value = a.point, .allocator = allocator)! }
    if b.insert { push($&points, .value = b.point, .allocator = allocator)! }
    _walk_validate_cut(
        .face      = original
        .boundary  = &boundary
        .points    = &points
        .start     = a.point
        .end       = b.point
        .plane     = plane
        .tolerance = model&._validation_tolerance
        .allocator = allocator
    )!
    -- Read the source winding independently of the chosen support normal.
    walk_points ::= DynamicArray#(g.Point#(Scalar))(
        .allocator = allocator, .capacity = range.count
    )!
    i :: UIntNative = 0
    while i < range.count {
        use ::= get(&boundary.uses, .index = range.start + i)!
        position ::= _boundary_use_point(.use = use, .points = &points)!
        push($&walk_points, .value = position, .allocator = allocator)!
        i = i + 1
    }
    positive ::= g.contour_orientation(.points = view(&walk_points), .plane = plane)!
    forward_cut: _BoundaryUse = (
        .origin   = ..some(.value = b.vertex)
        .edge     = cut
        .reversed = true
    )
    backward_cut: _BoundaryUse = (
        .origin   = ..some(.value = a.vertex)
        .edge     = cut
        .reversed = false
    )
    first_region ::= _split_candidate_region(
        .uses       = &boundary.uses
        .range      = range
        .offset     = boundary.first
        .count      = distance + 1
        .chord      = forward_cut
        .edge_count = counts.edges + added + 1
        .points     = &points
        .plane      = plane
        .positive   = positive
        .tolerance  = model&._validation_tolerance
        .allocator  = allocator
    )!
    second_region ::= _split_candidate_region(
        .uses       = &boundary.uses
        .range      = range
        .offset     = boundary.second
        .count      = range.count - distance + 1
        .chord      = backward_cut
        .edge_count = counts.edges + added + 1
        .points     = &points
        .plane      = plane
        .positive   = positive
        .tolerance  = model&._validation_tolerance
        .allocator  = allocator
    )!
    hole_contours ::= _split_hole_contours(
        .face       = original
        .boundary   = &boundary
        .points     = &points
        .edge_count = counts.edges + added + 1
        .allocator  = allocator
    )!
    first_points ::= view(&first_region.points)
    holes ::= _split_partition_holes(
        .holes      = &hole_contours
        .hole_count = original.loop_count - 1
        .exterior   = slice(
            &first_points, .start = 0, .count = get(&first_region.lengths, .index = 0)!
        )!
        .plane     = plane
        .tolerance = model&._validation_tolerance
        .allocator = allocator
    )!
    _split_validate_region(
        .holes     = &hole_contours
        .exterior  = &first_region
        .owners    = &holes
        .first     = true
        .tolerance = model&._validation_tolerance
        .allocator = allocator
    )!
    _split_validate_region(
        .holes     = &hole_contours
        .exterior  = &second_region
        .owners    = &holes
        .first     = false
        .tolerance = model&._validation_tolerance
        .allocator = allocator
    )!
    halfedges ::= DynamicArray#(HalfEdge)(
        .allocator = allocator, .capacity = [counts.halfedges + 6]
    )!
    loops ::= DynamicArray#(Loop)(.allocator = allocator, .capacity = counts.loops + 1)!
    faces ::= DynamicArray#(Face)(.allocator = allocator, .capacity = counts.faces + 1)!
    surfaces ::= DynamicArray#(SurfaceId)(.allocator = allocator, .capacity = counts.faces + 1)!
    output :: _SplitConnectivity = (
        .halfedges = ~halfedges
        .loops     = ~loops
        .faces     = ~faces
        .surfaces  = ~surfaces
    )
    i = 0
    while i <= counts.faces {
        current ::= i | convert#(.to: FaceId)(_)
        if i == counts.faces { current = face }
        source_face ::= face_info(model, .face = current)!
        loop_count ::= source_face.loop_count
        first_loop ::= length(&output.loops).count
        if current == face {
            loop_count = 1
            offset ::= boundary.first
            count ::= distance
            chord :: _BoundaryUse = (
                .origin   = ..some(.value = b.vertex)
                .edge     = cut
                .reversed = true
            )
            if i == counts.faces {
                offset = boundary.second
                count = range.count - distance
                chord = (.origin = ..some(.value = a.vertex), .edge = cut, .reversed = false)
            }
            cut_use: ?_BoundaryUse = ..some(.value = chord)
            _split_emit_loop(
                .destination = $&output
                .uses        = &boundary.uses
                .range       = range
                .offset      = offset
                .count       = count
                .chord       = cut_use
                .allocator   = allocator
            )!
            h :: UIntNative = 0
            while h < original.loop_count - 1 {
                if get(&holes, .index = h)! == [i != counts.faces] {
                    hole ::= get(&boundary.loops, .index = loop_index + 1 + h)!
                    no_chord: ?_BoundaryUse = ..none
                    _split_emit_loop(
                        .destination = $&output
                        .uses        = &boundary.uses
                        .range       = hole
                        .offset      = 0
                        .count       = hole.count
                        .chord       = no_chord
                        .allocator   = allocator
                    )!
                    loop_count = loop_count + 1
                }
                h = h + 1
            }
        } else {
            for entry in face_loops(model, .face = current)! {
                index ::= entry.id | convert#(.to: UIntNative)(_)
                refined ::= get(&boundary.loops, .index = index)!
                no_chord: ?_BoundaryUse = ..none
                _split_emit_loop(
                    .destination = $&output
                    .uses        = &boundary.uses
                    .range       = refined
                    .offset      = 0
                    .count       = refined.count
                    .chord       = no_chord
                    .allocator   = allocator
                )!
            }
        }
        record: Face = (
            .first_loop = [first_loop | convert#(.to: LoopId)(_)]
            .loop_count = loop_count
            .genus      = source_face.genus
            .reversed   = source_face.reversed
        )
        push($&output.faces, .value = record, .allocator = allocator)!
        push(
            $&output.surfaces
            .value     = face_surface_id(model, .face = current)!
            .allocator = allocator
        )!
        i = i + 1
    }
    edges ::= _split_pair_edges(
        .model      = model
        .halfedges  = &output.halfedges
        .first      = a
        .second     = b
        .edge_count = counts.edges + added + 1
        .allocator  = allocator
    )!
    topology: Topology = (
        ._vertex_count = counts.vertices + added
        ._edges        = ~edges
        ._halfedges    = ~output.halfedges
        ._loops        = ~output.loops
        ._faces        = ~output.faces
        ._closed       = model&._topology._closed
    )
    _validate_vertices(&topology, .allocator = allocator)!
    pools ::= _copy_geometry_pools(.source = &model&._geometry, .allocator = allocator)!
    domain ::= idx.IndexDomain(.allocator = allocator)!
    destination :: Model#(Scalar) = (
        ._domain               = ~domain
        ._topology             = ~topology
        ._points               = ~points
        ._geometry             = ~pools
        ._face_surfaces        = ~output.surfaces
        ._validation_tolerance = model&._validation_tolerance
    )
    split_a :: ?EdgeId = ..none
    split_b :: ?EdgeId = ..none
    if a.insert { split_a = ..some(.value = a.edge) }
    if b.insert { split_b = ..some(.value = b.edge) }
    result = ..ok(
        .model     = ~destination
        .cut_edge  = cut
        .cut_start = a.vertex
        .cut_end   = b.vertex
        .faces     = (
            face,
            counts.faces | convert#(.to: FaceId)(_)
        )
        ._source      = &model&._domain
        ._vertices    = counts.vertices
        ._edges       = counts.edges
        ._face_count  = counts.faces
        ._split_edges = (split_a, split_b)
        ._edge_parts  = parts
    )
}
