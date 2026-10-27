const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/117X_virtual_safety_contract_outcome_invalidation" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/117X_virtual_safety_contract_outcome_invalidation", "reference depends on a root that has ended");
}
