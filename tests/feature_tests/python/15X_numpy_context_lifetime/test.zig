const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/python/15X_numpy_context_lifetime" {
    try expectFrontendFailure("tests/feature_tests/python/15X_numpy_context_lifetime", "root that has ended");
}
