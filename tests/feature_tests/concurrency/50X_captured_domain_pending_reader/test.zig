const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 50X_captured_domain_pending_reader" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/50X_captured_domain_pending_reader", "pending execution");
}
