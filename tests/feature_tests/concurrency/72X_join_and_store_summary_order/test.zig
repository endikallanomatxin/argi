const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 72X_join_and_store_summary_order" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/72X_join_and_store_summary_order", "cannot hide a pending execution in opaque storage without its completion protocol");
}
