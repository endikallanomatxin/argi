const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/92X_virtual_safety_contract_domain_local_escape" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/92X_virtual_safety_contract_domain_local_escape", "local storage generation");
}
