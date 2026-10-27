const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/280X_generic_system_runtime_capture" {
    try buildExpectFailWithoutNoise("tests/feature_tests/execution/280X_generic_system_runtime_capture", "#run arguments must be compile-time constants", "failed without a diagnostic");
}
