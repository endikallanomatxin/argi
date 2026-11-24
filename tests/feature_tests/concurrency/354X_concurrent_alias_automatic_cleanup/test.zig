const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "354X_concurrent_alias_automatic_cleanup" {
    const path = "tests/feature_tests/concurrency/354X_concurrent_alias_automatic_cleanup";
    try support.expectFrontendFailure(path, "ordinary access overlaps concurrently shared storage");
}
