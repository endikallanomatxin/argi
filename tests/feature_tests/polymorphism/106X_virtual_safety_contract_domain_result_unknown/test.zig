const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/106X_virtual_safety_contract_domain_result_unknown" {
    try buildExpectFail("tests/feature_tests/polymorphism/106X_virtual_safety_contract_domain_result_unknown", "preserve its domain identities");
}
