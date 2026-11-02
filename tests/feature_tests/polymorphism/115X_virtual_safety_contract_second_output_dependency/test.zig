const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/115X_virtual_safety_contract_second_output_dependency" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/115X_virtual_safety_contract_second_output_dependency", "undeclared output dependency");
}
