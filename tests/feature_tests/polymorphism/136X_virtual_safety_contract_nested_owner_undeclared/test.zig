const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/136X_virtual_safety_contract_nested_owner_undeclared" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/136X_virtual_safety_contract_nested_owner_undeclared", "undeclared fresh output ownership");
}
