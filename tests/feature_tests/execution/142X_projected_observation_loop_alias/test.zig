const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/142X_projected_observation_loop_alias" {
    try buildExpectFail("tests/feature_tests/execution/142X_projected_observation_loop_alias", "observes storage after an aliased participant");
}
