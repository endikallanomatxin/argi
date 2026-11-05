const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 129X_nested_region_receiver_pending_writer" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/129X_nested_region_receiver_pending_writer", "pending execution");
}
