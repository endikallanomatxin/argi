const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/40X_empty_participants" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/40X_empty_participants", "at least one named participant", "panic");
}
