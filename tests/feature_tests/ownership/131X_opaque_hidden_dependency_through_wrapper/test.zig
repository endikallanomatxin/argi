const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/131X_opaque_hidden_dependency_through_wrapper" {
    try buildExpectFail(
        "tests/feature_tests/ownership/131X_opaque_hidden_dependency_through_wrapper",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
