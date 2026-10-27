const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/144X_projected_observation_args_alias" {
    try buildExpectFail("tests/feature_tests/execution/144X_projected_observation_args_alias", "observes storage after an aliased participant");
}
