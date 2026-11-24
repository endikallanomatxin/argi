const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "362X_concurrent_alias_branch_overlap" {
    const path = "tests/feature_tests/concurrency/362X_concurrent_alias_branch_overlap";
    try support.expectFrontendFailure(path, "ordinary access overlaps concurrently shared storage");
}
