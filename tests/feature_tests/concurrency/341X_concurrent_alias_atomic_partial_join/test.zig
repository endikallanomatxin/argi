const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "341X_concurrent_alias_atomic_partial_join" {
    const path = "tests/feature_tests/concurrency/341X_concurrent_alias_atomic_partial_join";
    try support.expectFrontendFailure(path, "pending execution");
}
