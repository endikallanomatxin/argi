const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "361X_concurrent_alias_forwarded_pending" {
    const path = "tests/feature_tests/concurrency/361X_concurrent_alias_forwarded_pending";
    try support.expectFrontendFailure(path, "pending execution");
}
