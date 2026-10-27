const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/146X_projected_observation_returned_reference" {
    try buildExpectFail("tests/feature_tests/execution/146X_projected_observation_returned_reference", "observes storage after an aliased participant");
}
