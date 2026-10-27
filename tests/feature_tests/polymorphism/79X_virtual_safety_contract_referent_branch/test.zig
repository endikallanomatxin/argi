const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/79X_virtual_safety_contract_referent_branch" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/79X_virtual_safety_contract_referent_branch", "cannot prove refers_to");
}
