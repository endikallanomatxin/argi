const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "342X_concurrent_alias_foreign_view" {
    const path = "tests/feature_tests/concurrency/342X_concurrent_alias_foreign_view";
    try support.expectFrontendFailure(path, "requires the module defining the nominal value type");
}
