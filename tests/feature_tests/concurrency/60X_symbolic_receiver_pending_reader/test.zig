const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 60X_symbolic_receiver_pending_reader" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/60X_symbolic_receiver_pending_reader", "pending execution");
}
