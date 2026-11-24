const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "339X_concurrent_alias_recovery_stale_ordinary" {
    const path = "tests/feature_tests/concurrency/339X_concurrent_alias_recovery_stale_ordinary";
    try support.expectFrontendFailure(path, "root that has ended");
}
