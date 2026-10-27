const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/86X_handle_local_borrow" {
    try buildExpectFail("tests/feature_tests/errors/86X_handle_local_borrow", "root that has ended");
}
