const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/109_virtual_safety_contract_domain_result_referent" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/109_virtual_safety_contract_domain_result_referent");
    try runExpect("tests/feature_tests/polymorphism/109_virtual_safety_contract_domain_result_referent", 0);
}
