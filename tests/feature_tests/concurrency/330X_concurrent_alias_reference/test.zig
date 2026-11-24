const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "330X_concurrent_alias_reference" {
    const path = "tests/feature_tests/concurrency/330X_concurrent_alias_reference";
    try support.expectFrontendFailure(path, "ConcurrentAlias requires a nominal value type");
}
