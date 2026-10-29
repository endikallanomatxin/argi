const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/278X_comptime_system_missing_dependency" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/execution/278X_comptime_system_missing_dependency", "no generic function named 'print' accepts arguments", "failed without a diagnostic");
}
