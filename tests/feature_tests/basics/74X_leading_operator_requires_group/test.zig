const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/74X_leading_operator_requires_group" {
    try buildExpectFail("tests/feature_tests/basics/74X_leading_operator_requires_group", "a leading operator requires scalar grouping");
}
