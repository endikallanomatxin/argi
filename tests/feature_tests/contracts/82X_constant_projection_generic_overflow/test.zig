const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/82X_constant_projection_generic_overflow" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/82X_constant_projection_generic_overflow", "compile-time integer arithmetic overflow", "panic");
}
