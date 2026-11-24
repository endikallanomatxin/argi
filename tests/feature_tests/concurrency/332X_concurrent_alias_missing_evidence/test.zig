const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "332X_concurrent_alias_missing_evidence" {
    const path = "tests/feature_tests/concurrency/332X_concurrent_alias_missing_evidence";
    try support.expectFrontendFailure(path, "concurrent sharing requires ConcurrentAlias evidence");
}
