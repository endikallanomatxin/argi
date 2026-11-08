const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "144X_isolated_callback_unknown_virtual" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/144X_isolated_callback_unknown_virtual", "isolated callback cannot access indirect or unresolved calls", "failed without a diagnostic");
}
