const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/73X_multiline_operation_missing_operand" {
    try buildExpectFail("tests/feature_tests/basics/73X_multiline_operation_missing_operand", "expected an expression after operator '+'");
}
