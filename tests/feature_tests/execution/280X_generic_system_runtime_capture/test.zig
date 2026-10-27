const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/280X_generic_system_runtime_capture" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/execution/280X_generic_system_runtime_capture", "#run arguments must be compile-time constants", "failed without a diagnostic");
}
