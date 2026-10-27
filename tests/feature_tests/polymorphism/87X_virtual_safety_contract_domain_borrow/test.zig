const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/87X_virtual_safety_contract_domain_borrow" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/87X_virtual_safety_contract_domain_borrow", "root that has ended");
}
