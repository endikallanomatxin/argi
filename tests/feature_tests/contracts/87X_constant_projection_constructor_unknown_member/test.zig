const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/87X_constant_projection_constructor_unknown_member" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/87X_constant_projection_constructor_unknown_member", "unknown associated element", "failed without a diagnostic");
}
