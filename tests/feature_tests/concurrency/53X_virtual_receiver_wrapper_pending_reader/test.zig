const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 53X_virtual_receiver_wrapper_pending_reader" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/53X_virtual_receiver_wrapper_pending_reader", "pending execution");
}
