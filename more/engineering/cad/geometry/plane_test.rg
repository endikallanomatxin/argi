_quad := () -> (.points: [4]Point#(Float64), .indices: [4]UIntNative) {
    points = (
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0)
    )
    indices = (0, 1, 2, 3)
}

test geometry_plane_orientation := (.system: System) -> !() {
    input ::= _quad()
    plane ::= [
        polygon_plane#(Float64)(
            .points    = view(&input.points)
            .indices   = &view(&input.indices)
            .start     = 0
            .count     = 4
            .tolerance = 0.000001
        )!
    ]
    testing.expect(plane.normal.x == 0.0 and plane.normal.y == 0.0 and plane.normal.z == 1.0)!
    input.indices = (3, 2, 1, 0)
    reverse ::= [
        polygon_plane#(Float64)(
            .points    = view(&input.points)
            .indices   = &view(&input.indices)
            .start     = 0
            .count     = 4
            .tolerance = 0.000001
        )!
    ]
    testing.expect(reverse.normal.z == -1.0)!
}

test geometry_rejects_nonplanar_face := (.system: System) -> !() {
    input ::= _quad()
    input.points[3].z = 0.01
    [
        testing.expect_error(
            .expected_reason = ..nonplanar_face
            .actual_result   = polygon_plane#(Float64)(
                .points    = view(&input.points)
                .indices   = &view(&input.indices)
                .start     = 0
                .count     = 4
                .tolerance = 0.000001
            )
        )!
    ]
}

test geometry_rejects_concave_and_crossing_faces := (.system: System) -> !() {
    input ::= _quad()
    input.points[2].x = 0.1
    input.points[2].y = 0.1
    [
        testing.expect_error(
            .expected_reason = ..nonconvex_face
            .actual_result   = polygon_plane#(Float64)(
                .points    = view(&input.points)
                .indices   = &view(&input.indices)
                .start     = 0
                .count     = 4
                .tolerance = 0.000001
            )
        )!
    ]
    input.points[2].x = 1.0
    input.points[2].y = 1.0
    input.indices = (0, 2, 1, 3)
    [
        testing.expect_error(
            .expected_reason = ..nonconvex_face
            .actual_result   = polygon_plane#(Float64)(
                .points    = view(&input.points)
                .indices   = &view(&input.indices)
                .start     = 0
                .count     = 4
                .tolerance = 0.000001
            )
        )!
    ]
}

test geometry_rejects_degenerate_faces := (.system: System) -> !() {
    input ::= _quad()
    input.points[2].x = 2.0
    input.points[2].y = 0.0
    [
        testing.expect_error(
            .expected_reason = ..degenerate_face
            .actual_result   = polygon_plane#(Float64)(
                .points    = view(&input.points)
                .indices   = &view(&input.indices)
                .start     = 0
                .count     = 3
                .tolerance = 0.000001
            )
        )!
    ]
    [
        testing.expect_error(
            .expected_reason = ..degenerate_face
            .actual_result   = polygon_plane#(Float64)(
                .points    = view(&input.points)
                .indices   = &view(&input.indices)
                .start     = 0
                .count     = 2
                .tolerance = 0.000001
            )
        )!
    ]
}

test geometry_rejects_invalid_tolerance_and_coordinates := (.system: System) -> !() {
    input ::= _quad()
    [
        testing.expect_error(
            .expected_reason = ..invalid_tolerance
            .actual_result   = polygon_plane#(Float64)(
                .points    = view(&input.points)
                .indices   = &view(&input.indices)
                .start     = 0
                .count     = 4
                .tolerance = 0.0
            )
        )!
    ]
    nan ::= sqrt#(Float64)(.value = -1.0).result
    [
        testing.expect_error(
            .expected_reason = ..invalid_tolerance
            .actual_result   = polygon_plane#(Float64)(
                .points    = view(&input.points)
                .indices   = &view(&input.indices)
                .start     = 0
                .count     = 4
                .tolerance = nan
            )
        )!
    ]
    input.points[1].x = nan
    [
        testing.expect_error(
            .expected_reason = ..invalid_coordinate
            .actual_result   = polygon_plane#(Float64)(
                .points    = view(&input.points)
                .indices   = &view(&input.indices)
                .start     = 0
                .count     = 4
                .tolerance = 0.000001
            )
        )!
    ]
}

test geometry_checks_indices_and_slice_bounds := (.system: System) -> !() {
    input ::= _quad()
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = polygon_plane#(Float64)(
                .points    = view(&input.points)
                .indices   = &view(&input.indices)
                .start     = 3
                .count     = 3
                .tolerance = 0.000001
            )
        )!
    ]
    input.indices[2] = 4
    [
        testing.expect_error(
            .expected_reason = ..out_of_bounds
            .actual_result   = polygon_plane#(Float64)(
                .points    = view(&input.points)
                .indices   = &view(&input.indices)
                .start     = 0
                .count     = 4
                .tolerance = 0.000001
            )
        )!
    ]
}

test geometry_rejects_numeric_overflow := (.system: System) -> !() {
    input ::= _quad()
    input.points[0].x = -1.0e308
    input.points[1].x = 1.0e308
    [
        testing.expect_error(
            .expected_reason = ..numeric_range
            .actual_result   = polygon_plane#(Float64)(
                .points    = view(&input.points)
                .indices   = &view(&input.indices)
                .start     = 0
                .count     = 4
                .tolerance = 0.000001
            )
        )!
    ]
}

test geometry_small_float32_polygon := (.system: System) -> !() {
    -- A valid small triangle must not disappear merely because squaring an
    -- unnormalized cross product underflows the chosen scalar type.
    points: [3]Point#(Float32) = (
        (0.0, 0.0, 0.0),
        (1.0e-12, 0.0, 0.0),
        (0.0, 1.0e-12, 0.0)
    )
    indices: [3]UIntNative = (0, 1, 2)
    plane ::= [
        polygon_plane#(Float32)(
            .points    = view(&points)
            .indices   = &view(&indices)
            .start     = 0
            .count     = 3
            .tolerance = 1.0e-15
        )!
    ]
    testing.expect(plane.normal.z > 0.999 and plane.normal.z < 1.001)!
}

test geometry_large_float64_polygon := (.system: System) -> !() {
    points: [3]Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (1.0e200, 0.0, 0.0),
        (0.0, 1.0e200, 0.0)
    )
    indices: [3]UIntNative = (0, 1, 2)
    plane ::= [
        polygon_plane#(Float64)(
            .points    = view(&points)
            .indices   = &view(&indices)
            .start     = 0
            .count     = 3
            .tolerance = 1.0e190
        )!
    ]
    testing.expect(plane.normal.z > 0.999 and plane.normal.z < 1.001)!
}
