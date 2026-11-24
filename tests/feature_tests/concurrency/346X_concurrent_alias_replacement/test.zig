const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "346X_concurrent_alias_replacement" {
    const path = "tests/feature_tests/concurrency/346X_concurrent_alias_replacement";
    try support.expectFrontendFailure(path, "ordinary access overlaps concurrently shared storage");
}
