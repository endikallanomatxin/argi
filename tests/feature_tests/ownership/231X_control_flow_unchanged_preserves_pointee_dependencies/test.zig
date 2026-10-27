const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/231X_control_flow_unchanged_preserves_pointee_dependencies" {
    try buildExpectFail(
        "tests/feature_tests/ownership/231X_control_flow_unchanged_preserves_pointee_dependencies",
        "reference depends on a root that has ended",
    );
}
