const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/109X_report_return_block_non_errable" {
    try buildExpectFail("tests/feature_tests/errors/109X_report_return_block_non_errable", "handle expects an Errable value");
}
