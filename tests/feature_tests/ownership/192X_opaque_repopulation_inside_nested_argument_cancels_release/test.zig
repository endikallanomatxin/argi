const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/192X_opaque_repopulation_inside_nested_argument_cancels_release" {
    try buildExpectFail(
        "tests/feature_tests/ownership/192X_opaque_repopulation_inside_nested_argument_cancels_release",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
