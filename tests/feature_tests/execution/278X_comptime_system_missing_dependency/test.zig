const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/278X_comptime_system_missing_dependency" {
    try buildExpectFailWithoutNoise("tests/feature_tests/execution/278X_comptime_system_missing_dependency", "omitted inputs have unavailable reach defaults", "failed without a diagnostic");
}
