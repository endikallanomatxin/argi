const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/199X_nested_initializer_propagates_input_post_state" {
    try buildExpectFail(
        "tests/feature_tests/ownership/199X_nested_initializer_propagates_input_post_state",
        "reference depends on a root that has ended",
    );
}
