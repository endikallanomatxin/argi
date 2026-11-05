const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 82X_opaque_take_pending_source" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/82X_opaque_take_pending_source", "concurrent access conflicts with a pending execution");
}
