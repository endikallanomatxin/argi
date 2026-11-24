const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "410X_joined_virtual_pending_recovery" {
    const path = "tests/feature_tests/concurrency/410X_joined_virtual_pending_recovery";
    try support.expectFrontendFailure(path, "pending execution");
}
