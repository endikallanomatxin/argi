const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/134X_projected_symbolic_participant_alias" {
    try expectFrontendFailure("tests/feature_tests/execution/134X_projected_symbolic_participant_alias", "observes storage after an aliased participant");
}
