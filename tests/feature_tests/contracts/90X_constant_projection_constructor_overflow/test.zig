const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/90X_constant_projection_constructor_overflow" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/90X_constant_projection_constructor_overflow", "compile-time integer arithmetic overflow", "failed without a diagnostic");
}
