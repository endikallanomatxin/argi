const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/192X_opaque_repopulation_inside_nested_argument_cancels_release" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/192X_opaque_repopulation_inside_nested_argument_cancels_release",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
