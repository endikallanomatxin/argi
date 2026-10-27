const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/148X_projected_observation_operand_effect" {
    try expectFrontendFailure("tests/feature_tests/execution/148X_projected_observation_operand_effect", "observes storage after an aliased participant");
}
