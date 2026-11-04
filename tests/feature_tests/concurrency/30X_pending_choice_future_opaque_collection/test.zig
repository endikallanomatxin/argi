const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 30X_pending_choice_future_opaque_collection" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/30X_pending_choice_future_opaque_collection", "pending execution");
}
