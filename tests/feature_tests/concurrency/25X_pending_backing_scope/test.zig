const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 25X_pending_backing_scope" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/25X_pending_backing_scope", "pending execution");
}
