const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/python/04X_object_lifetime" {
    try buildExpectFail("tests/feature_tests/python/04X_object_lifetime", "reference depends on a root that has ended");
}
