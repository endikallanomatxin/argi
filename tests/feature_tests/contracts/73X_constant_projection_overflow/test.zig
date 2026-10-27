const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/73X_constant_projection_overflow" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/73X_constant_projection_overflow", "compile-time integer arithmetic overflow", "panic");
}
