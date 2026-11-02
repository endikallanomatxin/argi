-- Deliberately use a different order for face records and loop storage.
-- Three triangular rings, one face with two loops, and no geometry.
test model_topology_without_geometry := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)

    edges ::= DynamicArray#(Edge)()!
    halfedges ::= DynamicArray#(HalfEdge)()!
    loops ::= DynamicArray#(Loop)()!
    faces ::= DynamicArray#(Face)()!
    i :: UIntNative = 0
    while i < 9 {
        id ::= i | convert#(.to: HalfEdgeId)(_)
        vertex ::= i | convert#(.to: VertexId)(_)
        edge ::= i | convert#(.to: EdgeId)(_)
        following ::= [i / 3] * 3 + [i + 1] % 3
        next_id ::= following | convert#(.to: HalfEdgeId)(_)
        loop_id ::= [i / 3] | convert#(.to: LoopId)(_)
        [
            push(
                $&halfedges
                .value = (
                    .origin = ..some(.value = vertex)
                    .edge   = edge
                    .next   = next_id
                    .loop   = loop_id
                )
            .allocator = allocator
            )!
        ]
        [push($&edges, .value = (.first = id, .second = ..none, .curve = ..none), .allocator = allocator)!]
        i = i + 1
    }
    [push($&loops, .value = (.first = (.value = 0), .count = 3), .allocator = allocator)!]
    [push($&loops, .value = (.first = (.value = 3), .count = 3), .allocator = allocator)!]
    [push($&loops, .value = (.first = (.value = 6), .count = 3), .allocator = allocator)!]
    [push($&faces, .value = (.first_loop = (.value = 1), .loop_count = 2, .genus = 0), .allocator = allocator)!]
    [push($&faces, .value = (.first_loop = (.value = 0), .loop_count = 1, .genus = 0), .allocator = allocator)!]
    connectivity: Topology = (
        ._vertex_count = 9
        ._edges        = ~edges
        ._halfedges    = ~halfedges
        ._loops        = ~loops
        ._faces        = ~faces
        ._closed       = false
    )
    [_validate_vertices(&connectivity, .allocator = allocator)!]
    counts ::= _topology_entity_counts(&connectivity)
    testing.expect(counts.vertices == 9 and counts.faces == 2 and counts.loops == 3)!
    outer ::= _topology_face_loop(&connectivity, .face = (.value = 0))!
    testing.expect(outer.value == 1)!
    [
        testing.expect([[_topology_face_loop(&connectivity, .face = (.value = 1))!].value == 0])!
    ]
    [
        testing.expect(
            [[_topology_face_info(&connectivity, .face = (.value = 0))!].loop_count == 2]
        )!
    ]
    visited :: UIntNative = 0
    for entry in [_topology_loop_halfedges(&connectivity, .loop = outer)!] {
        testing.expect(entry.halfedge.loop.value == 1)!
        testing.expect([halfedge_vertex(entry.halfedge)!].value >= 3)!
        visited = visited + 1
    }
    testing.expect(visited == 3)!
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = _topology_face_info(&connectivity, .face = (.value = 2))
        )!
    ]
}

test topology_id_conversions_are_infallible := () -> !() {
    offset: UIntNative = 42
    vertex: VertexId = offset | convert#(.to: VertexId)(_)
    edge: EdgeId = offset | convert#(.to: EdgeId)(_)
    face: FaceId = offset | convert#(.to: FaceId)(_)
    surface: SurfaceId = offset | convert#(.to: SurfaceId)(_)
    vertex_offset: UIntNative = vertex | convert#(.to: UIntNative)(_)
    edge_offset: UIntNative = edge | convert#(.to: UIntNative)(_)
    face_offset: UIntNative = face | convert#(.to: UIntNative)(_)
    surface_offset: UIntNative = surface | convert#(.to: UIntNative)(_)
    if [
        vertex_offset != offset
        or edge_offset != offset
        or face_offset != offset
        or surface_offset != offset
    ] {
        abort
    }
}
