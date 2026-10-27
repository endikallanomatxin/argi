const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/209X_input_post_state_before_early_return_is_preserved" {
    try buildExpectFail(
        "tests/feature_tests/ownership/209X_input_post_state_before_early_return_is_preserved",
        "reference depends on a root that has ended",
    );
}
