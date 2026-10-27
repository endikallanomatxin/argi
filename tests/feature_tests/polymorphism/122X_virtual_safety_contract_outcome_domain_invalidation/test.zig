const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/122X_virtual_safety_contract_outcome_domain_invalidation" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/122X_virtual_safety_contract_outcome_domain_invalidation", "reference depends on a root that has ended");
}
