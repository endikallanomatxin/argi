const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/76X_virtual_safety_contract_receiver_generation" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/76X_virtual_safety_contract_receiver_generation", "root that has ended");
}
