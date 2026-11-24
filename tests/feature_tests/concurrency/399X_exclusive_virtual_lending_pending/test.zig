const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "399X_exclusive_virtual_lending_pending" {
    const path = "tests/feature_tests/concurrency/399X_exclusive_virtual_lending_pending";
    try support.expectFrontendFailure(path, "concurrent access conflicts with a pending execution");
}
