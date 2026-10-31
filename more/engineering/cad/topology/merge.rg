MergeErrors := choice_union#(
    .a : BuildErrors,
    .b : (
        ..same_face,
        ..not_adjacent,
        ..not_coplanar,
        ..invalid_merge_boundary,
        ..missing_vertex,
        ..missing_boundary,
        ..unsupported_boundary
    )
)

-- IDs in history belong to the source and destination respectively. The source
-- domain borrow makes the origin of this operation explicit without self-borrows.
FaceMerge := #(.Scalar: Type: Float) (
    .model     : Model#(Scalar),
    ._source   : &idx.IndexDomain,
    ._vertices : DynamicArray#(UIntNative),
    ._edges    : DynamicArray#(UIntNative),
    ._faces    : DynamicArray#(UIntNative)
)

_MergeConnectivity := (
    .halfedges    : DynamicArray#(HalfEdge),
    .loops        : DynamicArray#(Loop),
    .faces        : DynamicArray#(Face),
    .surfaces     : DynamicArray#(SurfaceId),
    .halfedge_map : DynamicArray#(UIntNative)
)

_merge_emit_loop := #(.Provider: Type: Allocator) (
    .source      : &Topology,
    .removed     : &DynamicArray#(Bool),
    .vertices    : &DynamicArray#(UIntNative),
    .edges       : &DynamicArray#(UIntNative),
    .destination : $&_MergeConnectivity,
    .cycle       : _MergeLoop,
    .merged      : Bool,
    .allocator   : $&Provider
) -> (.result: Errable#(Void, MergeErrors)) {
    first ::= length(&destination&.halfedges).count
    loop_index ::= length(&destination&.loops).count
    loop_id ::= loop_index | convert#(.to: LoopId)(_)
    first_id ::= first | convert#(.to: HalfEdgeId)(_)
    loop: Loop = (.first = first_id, .count = cycle.count)
    push($&destination&.loops, .value = loop, .allocator = allocator)!
    current ::= cycle.first | convert#(.to: HalfEdgeId)(_)
    i :: UIntNative = 0
    while i < cycle.count {
        old_index ::= current | convert#(.to: UIntNative)(_)
        old ::= _topology_halfedge_info(source, .halfedge = current)!
        origin :: ?VertexId = ..none
        match old.origin {
            ..none {}
            ..some vertex {
                v ::= vertex.value | convert#(.to: UIntNative)(_)
                mapped ::= get(vertices, .index = v)!
                origin = ..some(
                    .value = [mapped | convert#(.to: VertexId)(_)]
                )
            }
        }
        old_edge ::= old.edge | convert#(.to: UIntNative)(_)
        new_edge ::= get(edges, .index = old_edge)!
        item: HalfEdge = (
            .origin   = origin
            .edge     = [new_edge | convert#(.to: EdgeId)(_)]
            .next     = [[[first + [i + 1] % cycle.count] | convert#(.to: HalfEdgeId)(_)]]
            .loop     = loop_id
            .reversed = old.reversed
            .pcurve   = old.pcurve
        )
        push($&destination&.halfedges, .value = item, .allocator = allocator)!
        mapped_slot ::= get_mutable_reference($&destination&.halfedge_map, .index = old_index)!
        mapped_slot&= first + i
        if merged {
            current = _merge_next(.topology = source, .removed = removed, .current = current)!
        } else {
            current = old.next
        }
        i = i + 1
    }
    result = ..ok Void()
}

merge_coplanar_faces := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .model: &Model#(Scalar), .first: FaceId, .second: FaceId, .allocator: $&Provider
) -> (.result: Errable#(FaceMerge#(Scalar), MergeErrors)) {
    face_info(model, .face = first)!
    face_info(model, .face = second)!
    if first == second {
        result = ..error(.reason = ..same_face)
        return
    }
    plane ::= _merge_plane(
        .model = model, .first = first, .second = second, .allocator = allocator
    )!
    selection ::= _merge_selection(
        .topology = &model&._topology, .first = first, .second = second, .allocator = allocator
    )!
    cycles ::= _merge_cycles(
        .model = model, .selection = &selection, .plane = plane, .allocator = allocator
    )!
    counts ::= entity_counts(model)
    vertex_map ::= DynamicArray#(UIntNative)(
        .allocator = allocator, .capacity = counts.vertices
    )!
    edge_map ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = counts.edges)!
    face_map ::= DynamicArray#(UIntNative)(.allocator = allocator, .capacity = counts.faces)!
    used ::= DynamicArray#(Bool)(.allocator = allocator, .capacity = counts.vertices)!
    points ::= DynamicArray#(g.Point#(Scalar))(
        .allocator = allocator, .capacity = counts.vertices
    )!
    i :: UIntNative = 0
    while i < counts.vertices {
        push($&used, .value = false, .allocator = allocator)!
        i = i + 1
    }
    i = 0
    while i < counts.halfedges {
        if get(&selection.removed, .index = i)! == false {
            item ::= get(&model&._topology._halfedges, .index = i)!
            match item.origin {
                ..none {}
                ..some vertex {
                    v ::= vertex.value | convert#(.to: UIntNative)(_)
                    slot ::= get_mutable_reference($&used, .index = v)!
                    slot&= true
                }
            }
        }
        i = i + 1
    }
    i = 0
    while i < counts.vertices {
        mapped ::= counts.vertices
        if get(&used, .index = i)! {
            mapped = length(&points).count
            push($&points, .value = get(&model&._points, .index = i)!, .allocator = allocator)!
        }
        push($&vertex_map, .value = mapped, .allocator = allocator)!
        i = i + 1
    }
    kept_edges :: UIntNative = 0
    i = 0
    while i < counts.edges {
        edge ::= get(&model&._topology._edges, .index = i)!
        old_first ::= edge.first | convert#(.to: UIntNative)(_)
        mapped ::= counts.edges
        if get(&selection.removed, .index = old_first)! == false {
            mapped = kept_edges
            kept_edges = kept_edges + 1
        }
        push($&edge_map, .value = mapped, .allocator = allocator)!
        i = i + 1
    }
    old_first_face ::= first | convert#(.to: UIntNative)(_)
    old_second_face ::= second | convert#(.to: UIntNative)(_)
    merged_face ::= old_first_face
    if old_first_face > old_second_face { merged_face = merged_face - 1 }
    i = 0
    while i < counts.faces {
        mapped ::= i
        if i > old_second_face { mapped = mapped - 1 }
        if i == old_second_face { mapped = merged_face }
        push($&face_map, .value = mapped, .allocator = allocator)!
        i = i + 1
    }
    halfedges ::= DynamicArray#(HalfEdge)(.allocator = allocator, .capacity = counts.halfedges)!
    loops ::= DynamicArray#(Loop)(.allocator = allocator, .capacity = counts.loops)!
    faces ::= DynamicArray#(Face)(.allocator = allocator, .capacity = counts.faces)!
    surfaces ::= DynamicArray#(SurfaceId)(.allocator = allocator, .capacity = counts.faces)!
    halfedge_map ::= DynamicArray#(UIntNative)(
        .allocator = allocator, .capacity = counts.halfedges
    )!
    i = 0
    while i < counts.halfedges {
        push($&halfedge_map, .value = counts.halfedges, .allocator = allocator)!
        i = i + 1
    }
    destination :: _MergeConnectivity = (
        .halfedges    = ~halfedges
        .loops        = ~loops
        .faces        = ~faces
        .surfaces     = ~surfaces
        .halfedge_map = ~halfedge_map
    )
    i = 0
    while i < counts.faces {
        if i != old_second_face {
            face_id ::= i | convert#(.to: FaceId)(_)
            original ::= face_info(model, .face = face_id)!
            loop_start ::= length(&destination.loops).count
            loop_count ::= original.loop_count
            genus ::= original.genus
            if i == old_first_face {
                loop_count = length(&cycles).count
                genus = 0
                j :: UIntNative = 0
                while j < loop_count {
                    _merge_emit_loop(
                        .source      = &model&._topology
                        .removed     = &selection.removed
                        .vertices    = &vertex_map
                        .edges       = &edge_map
                        .destination = $&destination
                        .cycle       = get(&cycles, .index = j)!
                        .merged      = true
                        .allocator   = allocator
                    )!
                    j = j + 1
                }
            } else {
                for boundary in face_loops(model, .face = face_id)! {
                    cycle: _MergeLoop = (
                        .first = [boundary.loop.first | convert#(.to: UIntNative)(_)]
                        .count = boundary.loop.count
                        .outer = false
                    )
                    _merge_emit_loop(
                        .source      = &model&._topology
                        .removed     = &selection.removed
                        .vertices    = &vertex_map
                        .edges       = &edge_map
                        .destination = $&destination
                        .cycle       = cycle
                        .merged      = false
                        .allocator   = allocator
                    )!
                }
            }
            item: Face = (
                .first_loop = [loop_start | convert#(.to: LoopId)(_)]
                .loop_count = loop_count
                .genus      = genus
                .reversed   = original.reversed
            )
            push($&destination.faces, .value = item, .allocator = allocator)!
            push(
                $&destination.surfaces
                .value     = face_surface_id(model, .face = face_id)!
                .allocator = allocator
            )!
        }
        i = i + 1
    }
    edges ::= DynamicArray#(Edge)(.allocator = allocator, .capacity = kept_edges)!
    i = 0
    while i < counts.edges {
        if get(&edge_map, .index = i)! != counts.edges {
            original ::= get(&model&._topology._edges, .index = i)!
            a ::= original.first | convert#(.to: UIntNative)(_)
            first_new ::= get(&destination.halfedge_map, .index = a)!
            second_new :: ?HalfEdgeId = ..none
            match original.second {
                ..none {}
                ..some paired {
                    b ::= paired.value | convert#(.to: UIntNative)(_)
                    mapped ::= get(&destination.halfedge_map, .index = b)!
                    second_new = ..some(
                        .value = [mapped | convert#(.to: HalfEdgeId)(_)]
                    )
                }
            }
            edge: Edge = (
                .first    = [first_new | convert#(.to: HalfEdgeId)(_)]
                .second   = second_new
                .curve    = original.curve
                .interval = original.interval
            )
            push($&edges, .value = edge, .allocator = allocator)!
        }
        i = i + 1
    }
    topology: Topology = (
        ._vertex_count = length(&points).count
        ._edges        = ~edges
        ._halfedges    = ~destination.halfedges
        ._loops        = ~destination.loops
        ._faces        = ~destination.faces
        ._closed       = model&._topology._closed
    )
    _validate_vertices(&topology, .allocator = allocator)!
    pools ::= _copy_geometry_pools(.source = &model&._geometry, .allocator = allocator)!
    domain ::= idx.IndexDomain(.allocator = allocator)!
    output: Model#(Scalar) = (
        ._domain               = ~domain
        ._topology             = ~topology
        ._points               = ~points
        ._geometry             = ~pools
        ._face_surfaces        = ~destination.surfaces
        ._validation_tolerance = model&._validation_tolerance
    )
    result = ..ok(
        .model     = ~output
        ._source   = &model&._domain
        ._vertices = ~vertex_map
        ._edges    = ~edge_map
        ._faces    = ~face_map
    )
}
