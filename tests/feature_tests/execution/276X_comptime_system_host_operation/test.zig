const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/276X_comptime_system_host_operation" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/execution/276X_comptime_system_host_operation", "host operation that is not enabled for compile-time execution", "failed without a diagnostic");
}
