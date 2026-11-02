const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/201X_nested_argument_propagates_input_post_state" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/201X_nested_argument_propagates_input_post_state",
        "reference depends on a root that has ended",
    );
}
