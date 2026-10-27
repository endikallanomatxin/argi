const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/120X_virtual_safety_contract_outcome_false_preservation" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/120X_virtual_safety_contract_outcome_false_preservation", "a storage transition is not permitted by this preservation contract");
}
