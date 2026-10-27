const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/217X_conditional_opaque_reference_source_hides_dependencies" {
    try buildExpectFail(
        "tests/feature_tests/ownership/217X_conditional_opaque_reference_source_hides_dependencies",
        "opaque storage hides a dependency",
    );
}
