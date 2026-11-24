const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "331X_concurrent_alias_generic_reference" {
    const path = "tests/feature_tests/concurrency/331X_concurrent_alias_generic_reference";
    try support.expectFrontendFailure(path, "ConcurrentAlias requires a nominal value type");
}
