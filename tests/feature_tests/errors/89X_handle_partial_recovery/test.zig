const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/89X_handle_partial_recovery" {
    try buildExpectFail("tests/feature_tests/errors/89X_handle_partial_recovery", "cannot be used");
}
