const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "357X_concurrent_alias_virtual_stale" {
    const path = "tests/feature_tests/concurrency/357X_concurrent_alias_virtual_stale";
    try support.expectFrontendFailure(path, "root that has ended");
}
