const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/106X_associated_argument_not_participant" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/106X_associated_argument_not_participant", "unknown argument name", "panic");
}
