const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "335X_concurrent_alias_nested_generation" {
    const path = "tests/feature_tests/concurrency/335X_concurrent_alias_nested_generation";
    try support.expectFrontendFailure(path, "root that has ended");
}
