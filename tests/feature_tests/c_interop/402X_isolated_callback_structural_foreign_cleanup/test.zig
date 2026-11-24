const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "402X_isolated_callback_structural_foreign_cleanup" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/402X_isolated_callback_structural_foreign_cleanup", "isolated virtual implementation cannot access foreign or unresolved functions", "failed without a diagnostic");
}
