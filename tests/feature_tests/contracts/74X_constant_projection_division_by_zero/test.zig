const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/74X_constant_projection_division_by_zero" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/74X_constant_projection_division_by_zero", "division by zero in compile-time expression", "panic");
}
