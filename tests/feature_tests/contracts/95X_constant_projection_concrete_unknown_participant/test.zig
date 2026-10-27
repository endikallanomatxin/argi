const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/95X_constant_projection_concrete_unknown_participant" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/95X_constant_projection_concrete_unknown_participant", "unknown or inaccessible type or contract in compile-time call arguments", "failed without a diagnostic");
}
