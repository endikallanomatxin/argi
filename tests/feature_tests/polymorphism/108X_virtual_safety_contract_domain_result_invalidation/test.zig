const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/108X_virtual_safety_contract_domain_result_invalidation" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/108X_virtual_safety_contract_domain_result_invalidation", "reference depends on a root that has ended");
}
