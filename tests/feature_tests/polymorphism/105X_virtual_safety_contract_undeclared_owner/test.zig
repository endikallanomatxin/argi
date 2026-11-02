const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/105X_virtual_safety_contract_undeclared_owner" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/105X_virtual_safety_contract_undeclared_owner", "undeclared fresh output ownership");
}
