const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "348X_concurrent_alias_wrapper_stale" {
    const path = "tests/feature_tests/concurrency/348X_concurrent_alias_wrapper_stale";
    try support.expectFrontendFailure(path, "root that has ended");
}
