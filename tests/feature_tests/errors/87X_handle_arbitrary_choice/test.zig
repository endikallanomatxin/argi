const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/87X_handle_arbitrary_choice" {
    try buildExpectFail("tests/feature_tests/errors/87X_handle_arbitrary_choice", "handle expects an Errable value");
}
