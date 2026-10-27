const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/59X_empty_expression_grouping" {
    try buildExpectFail("tests/feature_tests/basics/59X_empty_expression_grouping", "expression grouping requires exactly one expression");
}
