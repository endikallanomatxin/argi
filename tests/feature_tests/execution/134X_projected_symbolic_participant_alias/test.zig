const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/134X_projected_symbolic_participant_alias" {
    try buildExpectFail("tests/feature_tests/execution/134X_projected_symbolic_participant_alias", "observes storage after an aliased participant");
}
