const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/140X_opaque_mutation_hides_external_dependency" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/140X_opaque_mutation_hides_external_dependency",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}
