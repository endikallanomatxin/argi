const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/153X_static_contract_aliased_observation" {
    try expectFrontendFailure("tests/feature_tests/execution/153X_static_contract_aliased_observation", "observes storage after an aliased participant");
}
