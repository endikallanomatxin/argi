const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/50X_target_condition" {
    try buildExpectFailWithoutNoise("tests/feature_tests/system/50X_target_condition", "unknown OS, architecture, or ABI name", "failed without a diagnostic");
}
