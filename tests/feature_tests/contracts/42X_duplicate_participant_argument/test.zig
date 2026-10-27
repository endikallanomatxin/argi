const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/42X_duplicate_participant_argument" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/42X_duplicate_participant_argument", "duplicate argument", "panic");
}
