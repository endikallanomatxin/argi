const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/211X_distinct_return_post_states_are_joined" {
    try buildExpectFail(
        "tests/feature_tests/ownership/211X_distinct_return_post_states_are_joined",
        "reference depends on a root that has ended",
    );
}
