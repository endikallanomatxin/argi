const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/129X_virtual_safety_contract_outcome_result_alias" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/129X_virtual_safety_contract_outcome_result_alias", "a storage transition is not permitted by this preservation contract");
}
