const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/41X_value_participant" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/41X_value_participant", "participants must be named Type parameters", "panic");
}
