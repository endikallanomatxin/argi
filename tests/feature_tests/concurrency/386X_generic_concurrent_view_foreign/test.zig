const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "386X_generic_concurrent_view_foreign" {
    const path = "tests/feature_tests/concurrency/386X_generic_concurrent_view_foreign";
    try support.expectFrontendFailure(path, "trusted_concurrent_view requires the module defining the nominal value type");
}
