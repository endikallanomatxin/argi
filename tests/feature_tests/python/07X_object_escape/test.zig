const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/python/07X_object_escape" {
    try buildExpectFail("tests/feature_tests/python/07X_object_escape", "local storage generation");
}
