const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/148X_projected_observation_operand_effect" {
    try buildExpectFail("tests/feature_tests/execution/148X_projected_observation_operand_effect", "observes storage after an aliased participant");
}
