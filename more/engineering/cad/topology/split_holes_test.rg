test model_split_retains_hole := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    input ::= _planar_annulus()
    source ::= [
        from_planar_faces(
            .points           = view(&input.points)
            .vertex_indices   = view(&input.indices)
            .contour_lengths  = view(&input.lengths)
            .face_loop_counts = view(&input.face_loops)
            .require_closed   = false
        )!
    ]
    split ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = (.value = 0), .parameter = 0.125)
            .end   = (.halfedge = (.value = 2), .parameter = 0.875)
        )!
    ]
    counts ::= entity_counts(&split.model)
    testing.expect(counts.vertices == 10 and counts.edges == 11 and counts.faces == 2)!
    testing.expect(counts.loops == 3 and counts.halfedges == 12)!
    [
        testing.expect([[face_info(&split.model, .face = split.faces[0])!].loop_count == 2])!
    ]
    [
        testing.expect([[face_info(&split.model, .face = split.faces[1])!].loop_count == 1])!
    ]
    [
        testing.expect([[loop_info(&split.model, .loop = (.value = 1))!].count == 4])!
    ]
    testing.expect(entity_counts(&source).loops == 2)!
    merged ::= [
        merge_coplanar_faces(&split.model, .first = split.faces[0], .second = split.faces[1])!
    ]
    [
        testing.expect(
            [
                entity_counts(&merged.model).faces == 1
                and [[face_info(&merged.model, .face = (.value = 0))!].loop_count == 2]
            ]
        )!
    ]
}

_split_two_holes := #(.Scalar: Type: Float) () -> (
    .points     : [12]g.Point#(Scalar),
    .indices    : [12]UIntNative,
    .lengths    : [3]UIntNative,
    .face_loops : [1]UIntNative
) {
    points = (
        (0.0, 0.0, 0.0),
        (6.0, 0.0, 0.0),
        (6.0, 4.0, 0.0),
        (0.0, 4.0, 0.0),
        (1.0, 1.0, 0.0),
        (1.0, 3.0, 0.0),
        (2.0, 3.0, 0.0),
        (2.0, 1.0, 0.0),
        (4.0, 1.0, 0.0),
        (4.0, 3.0, 0.0),
        (5.0, 3.0, 0.0),
        (5.0, 1.0, 0.0)
    )
    indices = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
    lengths = (4, 4, 4)
    face_loops = (3)
}

test model_split_distributes_holes_float32 := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    input ::= _split_two_holes#(Float32)()
    source ::= [
        from_planar_faces(
            .points           = view(&input.points)
            .vertex_indices   = view(&input.indices)
            .contour_lengths  = view(&input.lengths)
            .face_loop_counts = view(&input.face_loops)
            .require_closed   = false
        )!
    ]
    split ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = (.value = 0), .parameter = 0.5)
            .end   = (.halfedge = (.value = 2), .parameter = 0.5)
        )!
    ]
    counts ::= entity_counts(&split.model)
    [
        testing.expect(
            [
                counts.faces == 2
                and counts.loops == 4
                and counts.vertices == 14
                and counts.edges == 15
            ]
        )!
    ]
    [
        testing.expect([[face_info(&split.model, .face = split.faces[0])!].loop_count == 2])!
    ]
    [
        testing.expect([[face_info(&split.model, .face = split.faces[1])!].loop_count == 2])!
    ]
    first_hole ::= [
        halfedge_vertex(
            [
                halfedge_info(
                    &split.model
                    .halfedge = [loop_info(&split.model, .loop = (.value = 1))!].first
                )!
            ]
        )!
    ]
    second_hole ::= [
        halfedge_vertex(
            [
                halfedge_info(
                    &split.model
                    .halfedge = [loop_info(&split.model, .loop = (.value = 3))!].first
                )!
            ]
        )!
    ]
    testing.expect(first_hole.value == 8 and second_hole.value == 4)!
    [
        testing.expect(
            [
                [face_surface_id(&split.model, .face = (.value = 0))!]
                == [face_surface_id(&split.model, .face = (.value = 1))!]
            ]
        )!
    ]
}

test model_split_reversing_cut_reassigns_hole := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    input ::= _planar_annulus()
    source ::= [
        from_planar_faces(
            .points           = view(&input.points)
            .vertex_indices   = view(&input.indices)
            .contour_lengths  = view(&input.lengths)
            .face_loop_counts = view(&input.face_loops)
            .require_closed   = false
        )!
    ]
    split ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = (.value = 2), .parameter = 0.875)
            .end   = (.halfedge = (.value = 0), .parameter = 0.125)
        )!
    ]
    [
        testing.expect([[face_info(&split.model, .face = split.faces[0])!].loop_count == 1])!
    ]
    [
        testing.expect([[face_info(&split.model, .face = split.faces[1])!].loop_count == 2])!
    ]
}

test model_split_rejects_hole_crossings_and_contacts := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    input ::= _planar_annulus()
    source ::= [
        from_planar_faces(
            .points           = view(&input.points)
            .vertex_indices   = view(&input.indices)
            .contour_lengths  = view(&input.lengths)
            .face_loop_counts = view(&input.face_loops)
            .require_closed   = false
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..intersecting_contours
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 0), .parameter = 0.5)
                .end   = (.halfedge = (.value = 2), .parameter = 0.5)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..intersecting_contours
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 0), .parameter = 0.25)
                .end   = (.halfedge = (.value = 2), .parameter = 0.75)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..intersecting_contours
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 0), .parameter = 0.249999875)
                .end   = (.halfedge = (.value = 2), .parameter = 0.750000125)
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..endpoint_not_on_boundary
            .actual_result   = split_planar_face(
                &source
                .face  = (.value = 0)
                .start = (.halfedge = (.value = 0), .parameter = 0.125)
                .end   = (.halfedge = (.value = 4), .parameter = 0.0)
            )
        )!
    ]
    testing.expect(entity_counts(&source).vertices == 8 and entity_counts(&source).loops == 2)!
}

test model_split_concave_face_retains_hole := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    points: [10]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (4.0, 0.0, 0.0),
        (4.0, 2.0, 0.0),
        (2.0, 2.0, 0.0),
        (2.0, 4.0, 0.0),
        (0.0, 4.0, 0.0),
        (0.5, 2.5, 0.0),
        (0.5, 3.5, 0.0),
        (1.5, 3.5, 0.0),
        (1.5, 2.5, 0.0)
    )
    indices: [10]UIntNative = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
    lengths: [2]UIntNative = (6, 4)
    loops: [1]UIntNative = (2)
    source ::= [
        from_planar_faces(
            .points           = view(&points)
            .vertex_indices   = view(&indices)
            .contour_lengths  = view(&lengths)
            .face_loop_counts = view(&loops)
            .require_closed   = false
        )!
    ]
    split ::= [
        split_planar_face(
            &source
            .face  = (.value = 0)
            .start = (.halfedge = (.value = 0), .parameter = 0.0)
            .end   = (.halfedge = (.value = 3), .parameter = 0.0)
        )!
    ]
    [
        testing.expect([[face_info(&split.model, .face = split.faces[0])!].loop_count == 1])!
    ]
    [
        testing.expect([[face_info(&split.model, .face = split.faces[1])!].loop_count == 2])!
    ]
    [
        testing.expect(
            [
                entity_counts(&split.model).vertices == 10
                and entity_counts(&split.model).edges == 11
            ]
        )!
    ]
}
