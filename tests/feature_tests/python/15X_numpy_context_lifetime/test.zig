const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/python/15X_numpy_context_lifetime" {
    try buildExpectFail("tests/feature_tests/python/15X_numpy_context_lifetime", "root that has ended");
}
