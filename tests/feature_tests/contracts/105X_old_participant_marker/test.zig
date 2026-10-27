const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/105X_old_participant_marker" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/105X_old_participant_marker", "declare contract participants on the name", "panic");
}
