const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/231X_control_flow_unchanged_preserves_pointee_dependencies" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/231X_control_flow_unchanged_preserves_pointee_dependencies",
        "reference depends on a root that has ended",
    );
}
