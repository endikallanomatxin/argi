test geometry_locates_contour_points := (.system: System) -> !() {
    points: [4]Point#(Float64) = (
        (0.0, 0.0, 2.0),
        (4.0, 0.0, 2.0),
        (4.0, 4.0, 2.0),
        (0.0, 4.0, 2.0)
    )
    plane: Plane#(Float64) = (.origin = points[0], .normal = (0.0, 0.0, -2.0))
    [
        testing.expect(
            [
                [
                    locate_in_planar_contour(
                        .points = view(&points), .point = (2.0, 2.0, 2.0), .plane = plane
                    )!
                ]
                == ..inside
            ]
        )!
    ]
    [
        testing.expect(
            [
                [
                    locate_in_planar_contour(
                        .points = view(&points), .point = (5.0, 2.0, 2.0), .plane = plane
                    )!
                ]
                == ..outside
            ]
        )!
    ]
    [
        testing.expect(
            [
                [
                    locate_in_planar_contour(
                        .points = view(&points), .point = (0.0, 2.0, 2.0), .plane = plane
                    )!
                ]
                == ..boundary
            ]
        )!
    ]
    [
        testing.expect(
            [
                [
                    locate_in_planar_contour(
                        .points = view(&points), .point = (0.0000005, 2.0, 2.0), .plane = plane
                    )!
                ]
                == ..boundary
            ]
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..nonplanar_face
            .actual_result   = locate_in_planar_contour(
                .points = view(&points), .point = (2.0, 2.0, 3.0), .plane = plane
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..invalid_tolerance
            .actual_result   = locate_in_planar_contour(
                .points = view(&points), .point = points[0], .plane = plane, .tolerance = 0.0
            )
        )!
    ]
}

test geometry_locates_concave_contour_float32 := (.system: System) -> !() {
    points: [6]Point#(Float32) = (
        (0.0, 0.0, 0.0),
        (2.0, 0.0, 0.0),
        (2.0, 1.0, 0.0),
        (1.0, 1.0, 0.0),
        (1.0, 2.0, 0.0),
        (0.0, 2.0, 0.0)
    )
    plane: Plane#(Float32) = (.origin = points[0], .normal = (0.0, 0.0, 1.0))
    [
        testing.expect(
            [
                [
                    locate_in_planar_contour(
                        .points = view(&points), .point = (0.5, 1.5, 0.0), .plane = plane
                    )!
                ]
                == ..inside
            ]
        )!
    ]
    [
        testing.expect(
            [
                [
                    locate_in_planar_contour(
                        .points = view(&points), .point = (1.5, 1.5, 0.0), .plane = plane
                    )!
                ]
                == ..outside
            ]
        )!
    ]
    [
        testing.expect(
            [
                [
                    locate_in_planar_contour(
                        .points    = view(&points)
                        .point     = (1.0, 1.0, 0.0)
                        .plane     = plane
                        .tolerance = 0.0001
                    )!
                ]
                == ..boundary
            ]
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..numerical_ambiguity
            .actual_result   = locate_in_planar_contour(
                .points = view(&points), .point = (1.0, 1.0, 0.0), .plane = plane
            )
        )!
    ]
}
