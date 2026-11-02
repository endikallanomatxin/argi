const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/119X_virtual_safety_contract_outcome_later_invalidation" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/119X_virtual_safety_contract_outcome_later_invalidation", "reference depends on a root that has ended");
}
