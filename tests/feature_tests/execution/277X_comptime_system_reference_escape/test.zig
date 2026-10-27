const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/277X_comptime_system_reference_escape" {
    try buildExpectFailWithoutNoise("tests/feature_tests/execution/277X_comptime_system_reference_escape", "function output cannot depend on a local storage generation", "failed without a diagnostic");
}
