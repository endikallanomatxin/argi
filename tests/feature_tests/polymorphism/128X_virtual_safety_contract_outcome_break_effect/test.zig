const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/128X_virtual_safety_contract_outcome_break_effect" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/128X_virtual_safety_contract_outcome_break_effect", "a storage transition is not permitted by this preservation contract");
}
