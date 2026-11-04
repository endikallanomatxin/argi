const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 45X_indirect_access_pending_reader" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/45X_indirect_access_pending_reader", "pending execution");
}
