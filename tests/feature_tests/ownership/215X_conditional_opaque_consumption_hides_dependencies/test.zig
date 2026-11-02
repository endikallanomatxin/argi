const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/215X_conditional_opaque_consumption_hides_dependencies" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/215X_conditional_opaque_consumption_hides_dependencies",
        "opaque storage hides a dependency",
    );
}
