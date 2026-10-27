const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/60X_multiple_expression_grouping" {
    try buildExpectFail("tests/feature_tests/basics/60X_multiple_expression_grouping", "expected ']' after grouped expression");
}
