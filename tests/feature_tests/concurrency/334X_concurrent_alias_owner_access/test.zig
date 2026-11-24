const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "334X_concurrent_alias_owner_access" {
    const path = "tests/feature_tests/concurrency/334X_concurrent_alias_owner_access";
    try support.expectFrontendFailure(path, "ordinary access overlaps concurrently shared storage");
}
