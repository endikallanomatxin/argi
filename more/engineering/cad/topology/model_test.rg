test model_tetrahedron_topology := (.system: System) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    points: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0)
    )
    indices: [12]UIntNative = (0, 2, 1, 0, 1, 3, 1, 2, 3, 2, 0, 3)
    face_lengths: [4]UIntNative = (3, 3, 3, 3)
    model ::= [
        from_any_length_faces(
            .points         = view(&points)
            .vertex_indices = view(&indices)
            .face_lengths   = view(&face_lengths)
            .tolerance      = 0.000001
            .require_closed = true
        )!
    ]
    testing.expect([face_info(&model, .face = (.value = 0))!].genus == 0)!
    counts ::= entity_counts(&model)
    testing.expect(counts.vertices == 4 and counts.edges == 6)!
    testing.expect(counts.halfedges == 12 and counts.loops == 4 and counts.faces == 4)!
    testing.expect(is_closed(&model).ok)!
    loop ::= face_loop(&model, .face = (.value = 0))!
    boundary ::= loop_info(&model, .loop = loop)!
    testing.expect(boundary.count == 3)!
    halfedge ::= halfedge_info(&model, .halfedge = boundary.first)!
    testing.expect([halfedge_vertex(halfedge)!].value == 0)!
    next ::= halfedge_info(&model, .halfedge = halfedge.next)!
    testing.expect([halfedge_vertex(next)!].value == 2)!
    match [opposite(&model, .halfedge = boundary.first)!] {
        ..none { [testing.fail()!] }
        ..some other {
            other_info ::= halfedge_info(&model, .halfedge = other.value)!
            testing.expect([halfedge_vertex(other_info)!].value == 2)!
        }
    }
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = point(&model, .vertex = (.value = 4))
        )!
    ]
}

test model_cube_float32_quad_faces := (.system: System) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    points: [8]g.Point#(Float32) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0),
        (1.0, 0.0, 1.0),
        (1.0, 1.0, 1.0),
        (0.0, 1.0, 1.0)
    )
    indices: [24]UIntNative = (
        0,
        3,
        2,
        1,
        4,
        5,
        6,
        7,
        0,
        1,
        5,
        4,
        1,
        2,
        6,
        5,
        2,
        3,
        7,
        6,
        3,
        0,
        4,
        7
    )
    face_lengths: [6]UIntNative = (4, 4, 4, 4, 4, 4)
    model ::= [
        from_any_length_faces(
            .points         = view(&points)
            .vertex_indices = view(&indices)
            .face_lengths   = view(&face_lengths)
            .tolerance      = 0.00001
            .require_closed = true
        )!
    ]
    counts ::= entity_counts(&model)
    testing.expect(counts.vertices == 8 and counts.edges == 12 and counts.halfedges == 24)!
    testing.expect(counts.faces == 6 and is_closed(&model).ok)!
    index :: UIntNative = 0
    while index < counts.halfedges {
        original: HalfEdgeId = [index | convert#(.to: HalfEdgeId)(_)]
        match [opposite(&model, .halfedge = original)!] {
            ..none { [testing.fail()!] }
            ..some paired {
                match [opposite(&model, .halfedge = paired.value)!] {
                    ..none { [testing.fail()!] }
                    ..some back {
                        testing.expect(back.value == original)!
                    }
                }
                a ::= halfedge_info(&model, .halfedge = original)!
                b ::= halfedge_info(&model, .halfedge = paired.value)!
                endpoint ::= halfedge_info(&model, .halfedge = a.next)!
                [
                    testing.expect([[halfedge_vertex(b)!] == [halfedge_vertex(endpoint)!]])!
                ]
            }
        }
        index = index + 1
    }
    loop ::= face_loop(&model, .face = (.value = 5))!
    boundary ::= loop_info(&model, .loop = loop)!
    testing.expect(boundary.count == 4)!
    plane ::= face_plane(&model, .face = (.value = 0))!
    testing.expect(plane.normal.z == -1.0)!
}
