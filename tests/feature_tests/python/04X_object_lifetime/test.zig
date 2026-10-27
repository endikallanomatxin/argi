const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/python/04X_object_lifetime" {
    try expectFrontendFailure("tests/feature_tests/python/04X_object_lifetime", "reference depends on a root that has ended");
}
