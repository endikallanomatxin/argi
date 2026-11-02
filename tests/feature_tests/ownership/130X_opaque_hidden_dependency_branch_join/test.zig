const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/130X_opaque_hidden_dependency_branch_join" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/130X_opaque_hidden_dependency_branch_join",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
