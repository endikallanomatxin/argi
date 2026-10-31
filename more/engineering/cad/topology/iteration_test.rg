test model_loop_halfedges_order_and_exhaustion := (.system: System) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    input ::= _triangle()
    faces: [1][3]UIntNative = ((2, 0, 1),)
    model ::= [
        from_equal_length_faces(
            .points = view(&input.points), .faces = view(&faces), .require_closed = false
        )!
    ]
    boundary ::= loop_halfedges(&model, .loop = (.value = 0))!
    expected: [3]VertexId = ((.value = 2), (.value = 0), (.value = 1))
    visited :: UIntNative = 0
    for entry in boundary {
        testing.expect(visited < 3)!
        [
            testing.expect([[entry.id | convert#(.to: UIntNative)(_)] == visited])!
        ]
        [
            testing.expect([[halfedge_vertex(entry.halfedge)!] == expected[visited]])!
        ]
        testing.expect(entry.halfedge.loop.value == 0)!
        info ::= halfedge_info(&model, .halfedge = entry.id)!
        testing.expect(info.next == entry.halfedge.next)!
        visited = visited + 1
    }
    testing.expect(visited == 3)!
    iterator ::= to_iterator(.value = &boundary)
    testing.expect(has_next(&iterator).ok and has_next(&iterator).ok)!
    first ::= next($&iterator).value
    testing.expect([halfedge_vertex(first.halfedge)!].value == 2)!
    next($&iterator)
    next($&iterator)
    testing.expect(has_next(&iterator).ok == false)!
    testing.expect(has_next(&iterator).ok == false)!
    -- Traversing the borrowed range starts a fresh cursor each time.
    again :: UIntNative = 0
    for entry in boundary {
        [
            testing.expect([[halfedge_vertex(entry.halfedge)!] == expected[again]])!
        ]
        again = again + 1
    }
    testing.expect(again == 3)!
}

test model_loop_halfedges_quad_and_invalid_id := (.system: System) -> !() {
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    points: [4]g.Point#(Float32) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    faces: [1][4]UIntNative = ((0, 1, 2, 3),)
    model ::= [
        from_equal_length_faces(
            .points = view(&points), .faces = view(&faces), .require_closed = false
        )!
    ]
    visited :: UIntNative = 0
    for entry in [loop_halfedges(&model, .loop = (.value = 0))!] {
        [
            testing.expect(
                [
                    [[[halfedge_vertex(entry.halfedge)!] | convert#(.to: UIntNative)(_)]]
                    == visited
                ]
            )!
        ]
        [
            testing.expect(
                [[entry.halfedge.next | convert#(.to: UIntNative)(_)] == [visited + 1] % 4]
            )!
        ]
        visited = visited + 1
    }
    testing.expect(visited == 4)!
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = loop_halfedges(&model, .loop = (.value = 1))
        )!
    ]
}
