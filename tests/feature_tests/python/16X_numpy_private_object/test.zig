const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/python/16X_numpy_private_object" {
    try buildExpectFail("tests/feature_tests/python/16X_numpy_private_object", "field '_object' is private");
}
