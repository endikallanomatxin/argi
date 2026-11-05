const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 157X_native_read_pending_writer" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/157X_native_read_pending_writer", "concurrent access conflicts with a pending execution");
}
