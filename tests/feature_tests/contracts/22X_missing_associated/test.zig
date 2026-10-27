const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/22X_missing_associated" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/22X_missing_associated", "missing argument", "panic");
}
