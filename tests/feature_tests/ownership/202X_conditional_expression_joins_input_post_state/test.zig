const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/202X_conditional_expression_joins_input_post_state" {
    try buildExpectFail(
        "tests/feature_tests/ownership/202X_conditional_expression_joins_input_post_state",
        "cannot select cleanup for conditional consumption",
    );
}
