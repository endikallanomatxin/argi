const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/128X_virtual_safety_contract_outcome_break_effect" {
    try buildExpectFail("tests/feature_tests/polymorphism/128X_virtual_safety_contract_outcome_break_effect", "a storage transition is not permitted by this preservation contract");
}
