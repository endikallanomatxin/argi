test model_equal_length_triangle_faces := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _triangle()
    tolerance: Float64 = 0.000001
    faces: [1][3]UIntNative = ((0, 1, 2),)
    model ::= [
        from_equal_length_faces(
            .points         = view(&input.points)
            .faces          = view(&faces)
            .tolerance      = tolerance
            .require_closed = false
        )!
    ]
    testing.expect(entity_counts(&model).faces == 1 and entity_counts(&model).halfedges == 3)!
    testing.expect(is_closed(&model).ok == false)!
}

test model_any_length_triangle_and_quad := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    points: [5]g.Point#(Float32) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0),
        (2.0, 0.0, 0.0)
    )
    indices: [7]UIntNative = (0, 1, 2, 3, 2, 1, 4)
    lengths: [2]UIntNative = (4, 3)
    model ::= [
        from_any_length_faces(
            .points         = view(&points)
            .vertex_indices = view(&indices)
            .face_lengths   = view(&lengths)
            .tolerance      = 0.00001
            .require_closed = false
        )!
    ]
    testing.expect(entity_counts(&model).faces == 2 and entity_counts(&model).edges == 6)!
    testing.expect([loop_info(&model, .loop = (.value = 0))!].count == 4)!
    second ::= loop_info(&model, .loop = (.value = 1))!
    testing.expect(second.count == 3 and second.first.value == 4)!
    match [opposite(&model, .halfedge = (.value = 1))!] {
        ..none { [testing.fail()!] }
        ..some other { [testing.expect(other.value.value == 4)!] }
    }
}

test model_rejects_invalid_face_lengths := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _triangle()
    short: [1]UIntNative = (2,)
    excessive: [1]UIntNative = (4,)
    empty: [0]UIntNative = ()
    native: UIntNative = 0
    maximum ::= integer_limits(.value = native).maximum
    overflow: [2]UIntNative = (3, maximum)
    [
        testing.expect_error(
            .expected_reason = ..degenerate_face
            .actual_result   = from_any_length_faces(
                .points         = view(&input.points)
                .vertex_indices = view(&input.indices)
                .face_lengths   = view(&short)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..invalid_face_lengths
            .actual_result   = from_any_length_faces(
                .points         = view(&input.points)
                .vertex_indices = view(&input.indices)
                .face_lengths   = view(&excessive)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..invalid_face_lengths
            .actual_result   = from_any_length_faces(
                .points         = view(&input.points)
                .vertex_indices = view(&input.indices)
                .face_lengths   = view(&empty)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..invalid_face_lengths
            .actual_result   = from_any_length_faces(
                .points         = view(&input.points)
                .vertex_indices = view(&input.indices)
                .face_lengths   = view(&overflow)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
}

test model_lengths_must_consume_all_indices := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _triangle()
    indices: [6]UIntNative = (0, 1, 2, 0, 2, 1)
    lengths: [1]UIntNative = (3,)
    [
        testing.expect_error(
            .expected_reason = ..invalid_face_lengths
            .actual_result   = from_any_length_faces(
                .points         = view(&input.points)
                .vertex_indices = view(&indices)
                .face_lengths   = view(&lengths)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
}

test model_equal_length_rejects_short_and_empty_faces := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _triangle()
    short: [1][2]UIntNative = ((0, 1),)
    zero: [1][0]UIntNative = ((),)
    empty: [0][3]UIntNative = ()
    [
        testing.expect_error(
            .expected_reason = ..degenerate_face
            .actual_result   = from_equal_length_faces(
                .points         = view(&input.points)
                .faces          = view(&short)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..degenerate_face
            .actual_result   = from_equal_length_faces(
                .points         = view(&input.points)
                .faces          = view(&zero)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..invalid_face_lengths
            .actual_result   = from_equal_length_faces(
                .points         = view(&input.points)
                .faces          = view(&empty)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
}

test model_equal_length_accepts_runtime_face_view := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _triangle()
    faces: [2][3]UIntNative = (
        (0, 1, 2),
        (99, 99, 99)
    )
    selected ::= slice(.self = &view(&faces), .start = 0, .count = 1)!
    model ::= [
        from_equal_length_faces(
            .points         = view(&input.points)
            .faces          = selected
            .tolerance      = 0.000001
            .require_closed = false
        )!
    ]
    testing.expect(entity_counts(&model).faces == 1 and entity_counts(&model).halfedges == 3)!
}

test model_equal_length_preserves_input_validation := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_) | $&_
    input ::= _triangle()
    faces: [1][3]UIntNative = ((0, 1, 3),)
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = from_equal_length_faces(
                .points         = view(&input.points)
                .faces          = view(&faces)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
    faces[0][2] = 0
    [
        testing.expect_error(
            .expected_reason = ..repeated_vertex
            .actual_result   = from_equal_length_faces(
                .points         = view(&input.points)
                .faces          = view(&faces)
                .tolerance      = 0.000001
                .require_closed = false
            )
        )!
    ]
}
