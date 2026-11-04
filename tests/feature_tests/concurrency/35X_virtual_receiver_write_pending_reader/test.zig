const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 35X_virtual_receiver_write_pending_reader" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/35X_virtual_receiver_write_pending_reader", "pending execution");
}
