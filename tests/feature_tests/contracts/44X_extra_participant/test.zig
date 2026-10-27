const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/44X_extra_participant" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/44X_extra_participant", "too many arguments", "panic");
}
