const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "143X_isolated_callback_unknown_native" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/143X_isolated_callback_unknown_native", "isolated callback cannot access foreign or unresolved functions", "failed without a diagnostic");
}
