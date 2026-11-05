const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 127X_nested_associated_region_pending_reader" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/127X_nested_associated_region_pending_reader", "pending execution");
}
