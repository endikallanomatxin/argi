FaceBridge := #(.Scalar: Type: Float) (
    .model           : Model#(Scalar),
    .face            : FaceId,
    .bridge_edge     : EdgeId,
    .exterior_vertex : VertexId,
    .hole_vertex     : VertexId,
    ._source         : &idx.IndexDomain,
    ._vertices       : UIntNative,
    ._edges          : UIntNative,
    ._faces          : UIntNative,
    ._split_edges    : [2] ?EdgeId,
    ._edge_parts     : [2]EdgeId
)

bridge_planar_face := #(.Scalar: Type: Float) (
    .model     : &Model#(Scalar),
    .face      : FaceId,
    .exterior  : BoundaryPoint#(Scalar),
    .hole      : BoundaryPoint#(Scalar),
    .allocator : Virtual#(Allocator)
) -> (.result: Errable#(FaceBridge#(Scalar), SplitErrors)) {

    original ::= face_info(model, .face = face)!
    plane ::= face_plane(model, .face = face)!
    if original.loop_count < 2 or original.genus != 0 {
        result = ..error(.reason = ..unsupported_boundary)
        return
    }
    outer_index ::= original.first_loop | convert#(.to: UIntNative)(_)
    hole_use ::= halfedge_info(model, .halfedge = hole.halfedge)!
    hole_index ::= hole_use.loop | convert#(.to: UIntNative)(_)
    if hole_index <= outer_index or hole_index - outer_index >= original.loop_count {
        result = ..error(.reason = ..endpoint_not_on_boundary)
        return
    }
    _require_linear_planar_boundaries(.model = model, .face = face)!
    counts ::= entity_counts(model)
    maximum ::= integer_limits(.value = counts.halfedges).maximum
    if [
        counts.halfedges > maximum - 6
        or counts.vertices > maximum - 2
        or counts.edges > maximum - 3
    ] {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    vertex ::= counts.vertices | convert#(.to: VertexId)(_)
    a ::= _split_endpoint(
        .model = model, .loop = original.first_loop, .location = exterior, .new_vertex = vertex
    )!
    added :: UIntNative = 0
    if a.insert { added = 1 }
    vertex = [[counts.vertices + added] | convert#(.to: VertexId)(_)]
    b ::= _split_endpoint(
        .model = model, .loop = hole_use.loop, .location = hole, .new_vertex = vertex
    )!
    part_a ::= counts.edges | convert#(.to: EdgeId)(_)
    part_b ::= [counts.edges + added] | convert#(.to: EdgeId)(_)
    if b.insert { added = added + 1 }
    bridge ::= [counts.edges + added] | convert#(.to: EdgeId)(_)
    parts: [2]EdgeId = (part_a, part_b)
    boundary ::= _split_refine(
        .model = model, .first = a, .second = b, .parts = parts, .allocator = allocator
    )!
    points ::= copy(&model&._points, .allocator = allocator)!
    if a.insert { push($&points, .value = a.point, .allocator = allocator)! }
    if b.insert { push($&points, .value = b.point, .allocator = allocator)! }
    _walk_validate_cut(
        .face      = original
        .boundary  = &boundary
        .points    = &points
        .start     = a.point
        .end       = b.point
        .bridge    = true
        .plane     = plane
        .tolerance = model&._validation_tolerance
        .allocator = allocator
    )!
    joined ::= DynamicArray#(_BoundaryUse)(.allocator = allocator)!
    outer ::= get(&boundary.loops, .index = outer_index)!
    inner ::= get(&boundary.loops, .index = hole_index)!
    _bridge_append(
        .uses        = &boundary.uses
        .destination = $&joined
        .range       = outer
        .offset      = boundary.first
        .allocator   = allocator
    )!
    forward: _BoundaryUse = (
        .origin   = ..some(.value = a.vertex)
        .edge     = bridge
        .reversed = false
    )
    push($&joined, .value = forward, .allocator = allocator)!
    _bridge_append(
        .uses        = &boundary.uses
        .destination = $&joined
        .range       = inner
        .offset      = boundary.second
        .allocator   = allocator
    )!
    backward: _BoundaryUse = (
        .origin   = ..some(.value = b.vertex)
        .edge     = bridge
        .reversed = true
    )
    push($&joined, .value = backward, .allocator = allocator)!
    halfedges ::= DynamicArray#(HalfEdge)(
        .allocator = allocator, .capacity = [counts.halfedges + 6]
    )!
    loops ::= DynamicArray#(Loop)(.allocator = allocator, .capacity = counts.loops - 1)!
    faces ::= DynamicArray#(Face)(.allocator = allocator, .capacity = counts.faces)!
    surfaces ::= copy(&model&._face_surfaces, .allocator = allocator)!
    output :: _SplitConnectivity = (
        .halfedges = ~halfedges
        .loops     = ~loops
        .faces     = ~faces
        .surfaces  = ~surfaces
    )
    i :: UIntNative = 0
    while i < counts.faces {
        id ::= i | convert#(.to: FaceId)(_)
        item ::= face_info(model, .face = id)!
        first_loop ::= length(&output.loops).count
        loop_count ::= item.loop_count
        if id == face {
            loop_count = loop_count - 1
            range: _BoundaryRange = (
                .start = 0
                .count = length(&joined).count
            )
            no_chord: ?_BoundaryUse = ..none
            _split_emit_loop(
                .destination = $&output
                .uses        = &joined
                .range       = range
                .offset      = 0
                .count       = range.count
                .chord       = no_chord
                .allocator   = allocator
            )!
        }
        for component in face_loops(model, .face = id)! {
            index ::= component.id | convert#(.to: UIntNative)(_)
            if id != face or [index != outer_index and index != hole_index] {
                range ::= get(&boundary.loops, .index = index)!
                no_chord: ?_BoundaryUse = ..none
                _split_emit_loop(
                    .destination = $&output
                    .uses        = &boundary.uses
                    .range       = range
                    .offset      = 0
                    .count       = range.count
                    .chord       = no_chord
                    .allocator   = allocator
                )!
            }
        }
        record: Face = (
            .first_loop = [first_loop | convert#(.to: LoopId)(_)]
            .loop_count = loop_count
            .genus      = item.genus
            .reversed   = item.reversed
        )
        push($&output.faces, .value = record, .allocator = allocator)!
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
    destination: Model#(Scalar) = (
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
        .model           = ~destination
        .face            = face
        .bridge_edge     = bridge
        .exterior_vertex = a.vertex
        .hole_vertex     = b.vertex
        ._source         = &model&._domain
        ._vertices       = counts.vertices
        ._edges          = counts.edges
        ._faces          = counts.faces
        ._split_edges    = (split_a, split_b)
        ._edge_parts     = parts
    )
}

_bridge_append := (
    .uses        : &DynamicArray#(_BoundaryUse),
    .destination : $&DynamicArray#(_BoundaryUse),
    .range       : _BoundaryRange,
    .offset      : UIntNative,
    .allocator   : Virtual#(Allocator)
) -> (.result: Errable#(Void, SplitErrors)) {

    cursor ::= offset
    i :: UIntNative = 0
    while i < range.count {
        item ::= get(uses, .index = range.start + cursor)!
        push(destination, .value = item, .allocator = allocator)!
        cursor = cursor + 1
        if cursor == range.count { cursor = 0 }
        i = i + 1
    }
    result = ..ok Void()
}
