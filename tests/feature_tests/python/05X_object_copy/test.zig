const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/python/05X_object_copy" {
    try buildExpectFail("tests/feature_tests/python/05X_object_copy", "cannot be copied implicitly");
}
