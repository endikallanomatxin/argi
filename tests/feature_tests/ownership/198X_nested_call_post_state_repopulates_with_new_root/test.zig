const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/198X_nested_call_post_state_repopulates_with_new_root" {
    try buildExpectFail(
        "tests/feature_tests/ownership/198X_nested_call_post_state_repopulates_with_new_root",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
