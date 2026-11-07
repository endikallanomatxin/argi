_planar_annulus := () -> (
    .points     : [8]g.Point#(Float64),
    .indices    : [8]UIntNative,
    .lengths    : [2]UIntNative,
    .face_loops : [1]UIntNative
) {
    points = (
        (0.0, 0.0, 0.0),
        (4.0, 0.0, 0.0),
        (4.0, 4.0, 0.0),
        (0.0, 4.0, 0.0),
        (1.0, 1.0, 0.0),
        (1.0, 3.0, 0.0),
        (3.0, 3.0, 0.0),
        (3.0, 1.0, 0.0)
    )
    indices = (0, 1, 2, 3, 4, 5, 6, 7)
    lengths = (4, 4)
    face_loops = (2)
}

test model_planar_face_with_hole := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    input ::= _planar_annulus()
    model ::= [
        from_planar_faces(
            .points           = view(&input.points)
            .vertex_indices   = view(&input.indices)
            .contour_lengths  = view(&input.lengths)
            .face_loop_counts = view(&input.face_loops)
            .require_closed   = false
        )!
    ]
    counts ::= entity_counts(&model)
    testing.expect(counts.faces == 1 and counts.loops == 2 and counts.edges == 8)!
    [
        testing.expect([[face_info(&model, .face = (.value = 0))!].loop_count == 2])!
    ]
    [
        testing.expect([[face_plane(&model, .face = (.value = 0))!].normal.z > 0.0])!
    ]
    testing.expect(is_closed(&model).ok == false)!
    visited :: UIntNative = 0
    for entry in [loop_halfedges(&model, .loop = (.value = 1))!] {
        [
            testing.expect(
                [[point(&model, .vertex = [halfedge_vertex(entry.halfedge)!])!].z == 0.0]
            )!
        ]
        visited = visited + 1
    }
    testing.expect(visited == 4)!
}

test model_planar_face_rejects_hole_winding := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    input ::= _planar_annulus()
    input.indices[5] = 7
    input.indices[7] = 5
    [
        testing.expect_error(
            .expected_reason = ..inconsistent_orientation
            .actual_result   = from_planar_faces(
                .points           = view(&input.points)
                .vertex_indices   = view(&input.indices)
                .contour_lengths  = view(&input.lengths)
                .face_loop_counts = view(&input.face_loops)
                .require_closed   = false
            )
        )!
    ]
}

test model_planar_face_rejects_bad_loop_counts := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    input ::= _planar_annulus()
    input.face_loops[0] = 3
    [
        testing.expect_error(
            .expected_reason = ..invalid_region_lengths
            .actual_result   = from_planar_faces(
                .points           = view(&input.points)
                .vertex_indices   = view(&input.indices)
                .contour_lengths  = view(&input.lengths)
                .face_loop_counts = view(&input.face_loops)
                .require_closed   = false
            )
        )!
    ]
}

test model_planar_faces_preserve_shared_coordinates_and_tolerance := (.system: System) -> !() {
    assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
    points: [6]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0000005),
        (0.0, 1.0, 0.0),
        (2.0, 0.0, 0.0),
        (2.0, 1.0, 0.0)
    )
    indices: [8]UIntNative = (0, 1, 2, 3, 1, 4, 5, 2)
    lengths: [2]UIntNative = (4, 4)
    face_loops: [2]UIntNative = (1, 1)
    tolerance: Float64 = 0.000001
    model ::= [
        from_planar_faces(
            .points           = view(&points)
            .vertex_indices   = view(&indices)
            .contour_lengths  = view(&lengths)
            .face_loop_counts = view(&face_loops)
            .tolerance        = tolerance
            .require_closed   = false
        )!
    ]
    testing.expect(validation_tolerance(&model).value == tolerance)!
    stored ::= point(&model, .vertex = (.value = 2))!
    [
        testing.expect(
            [stored.x == points[2].x and stored.y == points[2].y and stored.z == points[2].z]
        )!
    ]
    testing.expect(entity_counts(&model).vertices == 6 and entity_counts(&model).edges == 7)!
    f :: UIntNative = 0
    while f < 2 {
        face ::= f | convert#(.to: FaceId)(_)
        plane ::= face_plane(&model, .face = face)!
        for entry in [
            loop_halfedges(&model, .loop = [face_loop(&model, .face = face)!])!
        ] {
            p ::= [
                point(&model, .vertex = [halfedge_vertex(entry.halfedge)!])!
            ]
            distance ::= g.dot(
                .left = plane.normal, .right = g.between(.from = plane.origin, .to = p).result
            ).value
            testing.expect(distance <= tolerance and distance >= [0.0 - tolerance])!
        }
        f = f + 1
    }
}
