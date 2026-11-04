const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 20X_transitive_pending_read" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/20X_transitive_pending_read", "pending execution");
}
