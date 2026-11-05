const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 144X_native_write_pending_execution" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/144X_native_write_pending_execution", "concurrent access conflicts with a pending execution");
}
