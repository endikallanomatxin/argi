const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/133X_virtual_safety_contract_nested_nonchoice" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/133X_virtual_safety_contract_nested_nonchoice", "choice-valued output payload");
}
