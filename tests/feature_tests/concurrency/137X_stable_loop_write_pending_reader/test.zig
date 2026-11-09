const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency/137X_stable_loop_write_pending_reader" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/137X_stable_loop_write_pending_reader", "concurrent access conflicts with a pending execution");
}
