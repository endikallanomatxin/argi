const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/python/06X_private_handle" {
    try buildExpectFail("tests/feature_tests/python/06X_private_handle", "field '_handle' is private to its module");
}
