const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/69X_constant_projection_unknown_member" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/69X_constant_projection_unknown_member", "unknown associated constant", "panic");
}
