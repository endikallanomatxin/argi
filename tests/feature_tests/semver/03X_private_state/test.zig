const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/semver/03X_private_state" {
    try buildExpectFail("tests/feature_tests/semver/03X_private_state", "field '_text' is private to its module");
}
