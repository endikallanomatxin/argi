const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "349X_concurrent_alias_array_stale" {
    const path = "tests/feature_tests/concurrency/349X_concurrent_alias_array_stale";
    try support.expectFrontendFailure(path, "root that has ended");
}
