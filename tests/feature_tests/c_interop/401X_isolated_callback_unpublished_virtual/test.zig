const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "401X_isolated_callback_unpublished_virtual" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/401X_isolated_callback_unpublished_virtual", "isolated callback cannot access a virtual operation without a checked cross-execution guarantee", "failed without a diagnostic");
}
