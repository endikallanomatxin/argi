const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/120X_virtual_safety_contract_outcome_false_preservation" {
    try buildExpectFail("tests/feature_tests/polymorphism/120X_virtual_safety_contract_outcome_false_preservation", "a storage transition is not permitted by this preservation contract");
}
