const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/202X_conditional_expression_joins_input_post_state" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/202X_conditional_expression_joins_input_post_state",
        "cannot select cleanup for conditional consumption",
    );
}
