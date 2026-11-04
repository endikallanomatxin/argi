const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 34X_virtual_write_bound_pending_reader" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/34X_virtual_write_bound_pending_reader", "pending execution");
}
