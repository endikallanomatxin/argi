const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/python/16X_numpy_private_object" {
    try expectFrontendFailure("tests/feature_tests/python/16X_numpy_private_object", "field '_object' is private");
}
