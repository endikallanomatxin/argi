const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "338X_concurrent_alias_stale_shared" {
    const path = "tests/feature_tests/concurrency/338X_concurrent_alias_stale_shared";
    try support.expectFrontendFailure(path, "root that has ended");
}
