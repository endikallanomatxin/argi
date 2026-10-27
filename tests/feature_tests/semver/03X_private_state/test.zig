const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/semver/03X_private_state" {
    try expectFrontendFailure("tests/feature_tests/semver/03X_private_state", "field '_text' is private to its module");
}
