const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/91X_constant_projection_concrete_function_division_by_zero" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/91X_constant_projection_concrete_function_division_by_zero", "division by zero in compile-time expression", "failed without a diagnostic");
}
