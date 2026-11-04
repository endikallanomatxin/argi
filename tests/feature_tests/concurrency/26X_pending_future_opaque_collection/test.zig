const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 26X_pending_future_opaque_collection" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/26X_pending_future_opaque_collection", "pending execution");
}
