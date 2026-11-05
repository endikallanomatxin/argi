const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 81X_opaque_store_pending_destination" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/81X_opaque_store_pending_destination", "concurrent access conflicts with a pending execution");
}
