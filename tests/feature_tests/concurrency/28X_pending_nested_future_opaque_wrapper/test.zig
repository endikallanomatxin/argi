const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 28X_pending_nested_future_opaque_wrapper" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/28X_pending_nested_future_opaque_wrapper", "pending execution");
}
