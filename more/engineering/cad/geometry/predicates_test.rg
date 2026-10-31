test geometry_candidate_plane_does_not_certify_polygon := (.system: System) -> !() {
    points: [4]Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.1)
    )
    indices: [4]UIntNative = (0, 1, 2, 3)
    borrowed ::= view(&indices)
    candidate ::= [
        _plane_from_corner(
            .a = points[0], .b = points[1], .c = points[2], .tolerance = 0.000001
        )!
    ]
    testing.expect(candidate.normal.z == 1.0)!
    [
        testing.expect_error(
            .expected_reason = ..nonplanar_face
            .actual_result   = _check_polygon_planarity(
                .points    = view(&points)
                .indices   = &borrowed
                .start     = 0
                .count     = 4
                .plane     = candidate
                .tolerance = 0.000001
            )
        )!
    ]
}

test geometry_planarity_tolerance_boundary := (.system: System) -> !() {
    points :: [4]Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0000005)
    )
    indices: [4]UIntNative = (0, 1, 2, 3)
    borrowed ::= view(&indices)
    candidate ::= [
        _plane_from_corner(
            .a = points[0], .b = points[1], .c = points[2], .tolerance = 0.000001
        )!
    ]
    [
        _check_polygon_planarity(
            .points    = view(&points)
            .indices   = &borrowed
            .start     = 0
            .count     = 4
            .plane     = candidate
            .tolerance = 0.000001
        )!
    ]
    points[3] = (0.0, 1.0, 0.000002)
    [
        testing.expect_error(
            .expected_reason = ..nonplanar_face
            .actual_result   = _check_polygon_planarity(
                .points    = view(&points)
                .indices   = &borrowed
                .start     = 0
                .count     = 4
                .plane     = candidate
                .tolerance = 0.000001
            )
        )!
    ]
}
