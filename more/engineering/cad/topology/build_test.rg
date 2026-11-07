_triangle := () -> (
    .points: [3]g.Point#(Float64), .indices: [3]UIntNative, .face_lengths: [1]UIntNative
) {
    points = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    indices = (0, 1, 2)
    face_lengths = (3,)
}

test model_open_patch_and_closure := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    input ::= _triangle()
    model ::= [
        from_any_length_faces(
            .points         = view(&input.points)
            .vertex_indices = view(&input.indices)
            .face_lengths   = view(&input.face_lengths)
            .tolerance      = 0.000001
            .require_closed = false
        )!
    ]
    testing.expect(is_closed(&model).ok == false)!
    testing.expect(entity_counts(&model).edges == 3)!
    match [opposite(&model, .halfedge = (.value = 0))!] {
        ..none {}
        ..some _ { [testing.fail()!] }
    }
    [
        testing.expect_error(
            .expected_reason = ..open_boundary
            .actual_result   = from_any_length_faces(
                .points         = view(&input.points)
                .vertex_indices = view(&input.indices)
                .face_lengths   = view(&input.face_lengths)
                .tolerance      = 0.000001
                .require_closed = true
            )
        )!
    ]
}

test model_rejects_bad_vertex_indices := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    input ::= _triangle()
    input.indices[2] = 3
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = from_any_length_faces(
                .points         = view(&input.points)
                .vertex_indices = view(&input.indices)
                .face_lengths   = view(&input.face_lengths)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
    input.indices[2] = 0
    [
        testing.expect_error(
            .expected_reason = ..repeated_vertex
            .actual_result   = from_any_length_faces(
                .points         = view(&input.points)
                .vertex_indices = view(&input.indices)
                .face_lengths   = view(&input.face_lengths)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
}

test model_rejects_inconsistent_orientation := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    input ::= _triangle()
    indices: [6]UIntNative = (0, 1, 2, 0, 1, 2)
    face_lengths: [2]UIntNative = (3, 3)
    [
        testing.expect_error(
            .expected_reason = ..inconsistent_orientation
            .actual_result   = from_any_length_faces(
                .points         = view(&input.points)
                .vertex_indices = view(&indices)
                .face_lengths   = view(&face_lengths)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
}

test model_rejects_nonmanifold_edge := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    input ::= _triangle()
    indices: [9]UIntNative = (0, 1, 2, 0, 2, 1, 0, 1, 2)
    face_lengths: [3]UIntNative = (3, 3, 3)
    [
        testing.expect_error(
            .expected_reason = ..nonmanifold_edge
            .actual_result   = from_any_length_faces(
                .points         = view(&input.points)
                .vertex_indices = view(&indices)
                .face_lengths   = view(&face_lengths)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
}

test model_rejects_pinched_vertex := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    points: [5]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (-1.0, 0.0, 0.0),
        (0.0, -1.0, 0.0)
    )
    indices: [6]UIntNative = (0, 1, 2, 0, 3, 4)
    face_lengths: [2]UIntNative = (3, 3)
    [
        testing.expect_error(
            .expected_reason = ..nonmanifold_vertex
            .actual_result   = from_any_length_faces(
                .points         = view(&points)
                .vertex_indices = view(&indices)
                .face_lengths   = view(&face_lengths)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
}

test model_rejects_unused_vertex := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    points: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (9.0, 9.0, 9.0)
    )
    input ::= _triangle()
    [
        testing.expect_error(
            .expected_reason = ..unused_vertex
            .actual_result   = from_any_length_faces(
                .points         = view(&points)
                .vertex_indices = view(&input.indices)
                .face_lengths   = view(&input.face_lengths)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
}

test model_owns_input_and_checks_query_bounds := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    input ::= _triangle()
    model ::= [
        from_any_length_faces(
            .points         = view(&input.points)
            .vertex_indices = view(&input.indices)
            .face_lengths   = view(&input.face_lengths)
            .tolerance      = 0.000001
            .require_closed = false
        )!
    ]
    input.points[0].x = 50.0
    input.indices[0] = 2
    testing.expect([point(&model, .vertex = (.value = 0))!].x == 0.0)!
    [
        testing.expect(
            [[halfedge_vertex([halfedge_info(&model, .halfedge = (.value = 0))!])!].value == 0]
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = halfedge_info(&model, .halfedge = (.value = 3))
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = edge_info(&model, .edge = (.value = 3))
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = loop_info(&model, .loop = (.value = 1))
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = face_loop(&model, .face = (.value = 1))
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = face_plane(&model, .face = (.value = 1))
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = opposite(&model, .halfedge = (.value = 3))
        )!
    ]
}

test model_boundary_vertex_fans := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    points: [4]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    indices: [6]UIntNative = (0, 1, 2, 0, 2, 3)
    face_lengths: [2]UIntNative = (3, 3)
    model ::= [
        from_any_length_faces(
            .points         = view(&points)
            .vertex_indices = view(&indices)
            .face_lengths   = view(&face_lengths)
            .tolerance      = 0.000001
            .require_closed = false
        )!
    ]
    testing.expect(entity_counts(&model).edges == 5 and is_closed(&model).ok == false)!
    match [opposite(&model, .halfedge = (.value = 2))!] {
        ..none { [testing.fail()!] }
        ..some other { [testing.expect(other.value.value == 3)!] }
    }
}

test model_rejects_closed_pinched_vertex := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    points: [7]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0),
        (-1.0, 0.0, 0.0),
        (0.0, -1.0, 0.0),
        (0.0, 0.0, -1.0)
    )
    indices: [24]UIntNative = (
        0,
        2,
        1,
        0,
        1,
        3,
        1,
        2,
        3,
        2,
        0,
        3,
        0,
        5,
        4,
        0,
        4,
        6,
        4,
        5,
        6,
        5,
        0,
        6
    )
    face_lengths: [8]UIntNative = (3, 3, 3, 3, 3, 3, 3, 3)
    [
        testing.expect_error(
            .expected_reason = ..nonmanifold_vertex
            .actual_result   = from_any_length_faces(
                .points         = view(&points)
                .vertex_indices = view(&indices)
                .face_lengths   = view(&face_lengths)
                .tolerance      = 0.000001
                .require_closed = true
            )
        )!
    ]
}
