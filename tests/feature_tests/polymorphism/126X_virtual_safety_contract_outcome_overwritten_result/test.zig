const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/126X_virtual_safety_contract_outcome_overwritten_result" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/126X_virtual_safety_contract_outcome_overwritten_result", "reference depends on a root that has ended");
}
