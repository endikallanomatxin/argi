const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/187X_opaque_release_then_write_double_wrapper_repopulates" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/187X_opaque_release_then_write_double_wrapper_repopulates",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
