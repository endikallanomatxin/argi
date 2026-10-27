const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/semver/04X_view_lifetime" {
    try expectFrontendFailure("tests/feature_tests/semver/04X_view_lifetime", "reference depends on a root that has ended");
}
