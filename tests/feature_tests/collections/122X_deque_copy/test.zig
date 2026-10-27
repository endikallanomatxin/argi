const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/122X_deque_copy" {
    try buildExpectFail("tests/feature_tests/collections/122X_deque_copy", "cannot be copied implicitly");
}
