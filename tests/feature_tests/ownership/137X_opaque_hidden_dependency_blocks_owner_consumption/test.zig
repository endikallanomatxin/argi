const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/137X_opaque_hidden_dependency_blocks_owner_consumption" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/137X_opaque_hidden_dependency_blocks_owner_consumption",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
