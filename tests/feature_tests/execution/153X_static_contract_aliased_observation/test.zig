const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/153X_static_contract_aliased_observation" {
    try buildExpectFail("tests/feature_tests/execution/153X_static_contract_aliased_observation", "observes storage after an aliased participant");
}
