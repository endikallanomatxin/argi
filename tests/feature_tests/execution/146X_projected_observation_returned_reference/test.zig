const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/146X_projected_observation_returned_reference" {
    try expectFrontendFailure("tests/feature_tests/execution/146X_projected_observation_returned_reference", "observes storage after an aliased participant");
}
