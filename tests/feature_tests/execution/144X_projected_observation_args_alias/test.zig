const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/144X_projected_observation_args_alias" {
    try expectFrontendFailure("tests/feature_tests/execution/144X_projected_observation_args_alias", "observes storage after an aliased participant");
}
