test geometry_frame_directions_project_heading_and_preserve_scale_invariance := (
    .system : System
) -> !() {
    scales: [3]Float64 = (0.00000000000000000001, 1.0, 100000000000000000000.0)
    for scale in scales {
        value ::= [
            frame_from_directions#(Float64)(
                .origin      = (3.0, 4.0, 5.0)
                .normal      = (0.6 * scale, 0.0, 0.8 * scale)
                .x_direction = (1.4 * scale, 0.0, 0.2 * scale)
            )!
        ]
        [validate_frame(value)!]
        testing.expect(_absolute(value.x.x - 0.8).result < 0.000000000001)!
        testing.expect(_absolute(value.x.z + 0.6).result < 0.000000000001)!
        testing.expect(_absolute(value.y.y - 1.0).result < 0.000000000001)!
        [
            testing.expect(
                value.origin.x == 3.0 and value.origin.y == 4.0 and value.origin.z == 5.0
            )!
        ]
        reversed ::= [
            frame_from_directions#(Float64)(
                .origin      = value.origin
                .normal      = (-0.6 * scale, 0.0, -0.8 * scale)
                .x_direction = value.x
            )!
        ]
        testing.expect(dot(.left = reversed.x, .right = value.x).value > 0.999999)!
        testing.expect(dot(.left = reversed.y, .right = value.y).value < -0.999999)!
    }
    single ::= [
        frame_from_directions#(Float32)(
            .origin = (0.0, 0.0, 0.0), .normal = (0.0, 0.0, 2.0), .x_direction = (3.0, 0.0, 4.0)
        )!
    ]
    testing.expect(single.x.x == 1.0 and single.y.y == 1.0 and single.z.z == 1.0)!
}

test geometry_frame_directions_reject_degenerate_and_ambiguous_headings := (.system: System) -> !() {
    origin: Point#(Float64) = (0.0, 0.0, 0.0)
    normal: Displacement#(Float64) = (0.0, 0.0, 1.0)
    [
        testing.expect_error(
            .actual_result = frame_from_directions#(Float64)(
                .origin = origin, .normal = normal, .x_direction = normal
            )
            .expected_reason = ..degenerate_face
        )!
    ]
    [
        testing.expect_error(
            .actual_result = frame_from_directions#(Float64)(
                .origin = origin, .normal = normal, .x_direction = (0.0, 0.0, 0.0)
            )
            .expected_reason = ..degenerate_face
        )!
    ]
    [
        testing.expect_error(
            .actual_result = frame_from_directions#(Float64)(
                .origin = origin, .normal = (0.0, 0.0, 0.0), .x_direction = normal
            )
            .expected_reason = ..degenerate_face
        )!
    ]
    [
        testing.expect_error(
            .actual_result = frame_from_directions#(Float64)(
                .origin      = origin
                .normal      = normal
                .x_direction = (0.0000000000000001, 0.0, 1.0)
            )
            .expected_reason = ..numerical_ambiguity
        )!
    ]
    nan ::= sqrt#(Float64)(.value = -1.0).result
    [
        testing.expect_error(
            .actual_result = frame_from_directions#(Float64)(
                .origin = origin, .normal = normal, .x_direction = (nan, 0.0, 0.0)
            )
            .expected_reason = ..invalid_coordinate
        )!
    ]
    [
        testing.expect_error(
            .actual_result = frame_from_directions#(Float64)(
                .origin = (nan, 0.0, 0.0), .normal = normal, .x_direction = normal
            )
            .expected_reason = ..invalid_coordinate
        )!
    ]
}
