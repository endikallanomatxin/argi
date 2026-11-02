const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/196X_opaque_expression_order_release_then_repopulate" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/196X_opaque_expression_order_release_then_repopulate",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
