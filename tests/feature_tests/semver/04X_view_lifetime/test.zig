const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/semver/04X_view_lifetime" {
    try buildExpectFail("tests/feature_tests/semver/04X_view_lifetime", "reference depends on a root that has ended");
}
