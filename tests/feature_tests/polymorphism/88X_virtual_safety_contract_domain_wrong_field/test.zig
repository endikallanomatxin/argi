const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/88X_virtual_safety_contract_domain_wrong_field" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/88X_virtual_safety_contract_domain_wrong_field", "undeclared output dependency");
}
