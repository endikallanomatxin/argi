const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "359X_concurrent_alias_union_overlap" {
    const path = "tests/feature_tests/concurrency/359X_concurrent_alias_union_overlap";
    try support.expectFrontendFailure(path, "ordinary access overlaps concurrently shared storage");
}
