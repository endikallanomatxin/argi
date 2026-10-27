const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/69X_virtual_safety_contract_dependency" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/69X_virtual_safety_contract_dependency", "undeclared output dependency involving input 'other'");
}
