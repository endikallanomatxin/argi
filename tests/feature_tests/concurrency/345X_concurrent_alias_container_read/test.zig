const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "345X_concurrent_alias_container_read" {
    const path = "tests/feature_tests/concurrency/345X_concurrent_alias_container_read";
    try support.expectFrontendFailure(path, "ordinary access overlaps concurrently shared storage");
}
