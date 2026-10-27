const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/20X_unknown_participant" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/20X_unknown_participant", "unknown argument name", "panic");
}
