const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/19X_missing_participant" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/19X_missing_participant", "missing argument", "panic");
}
