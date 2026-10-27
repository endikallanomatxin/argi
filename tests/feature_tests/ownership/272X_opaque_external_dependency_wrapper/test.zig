const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/272X_opaque_external_dependency_wrapper" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/272X_opaque_external_dependency_wrapper",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
