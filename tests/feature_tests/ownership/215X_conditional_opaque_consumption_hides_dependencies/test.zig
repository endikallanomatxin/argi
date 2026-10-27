const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/215X_conditional_opaque_consumption_hides_dependencies" {
    try buildExpectFail(
        "tests/feature_tests/ownership/215X_conditional_opaque_consumption_hides_dependencies",
        "opaque storage hides a dependency",
    );
}
