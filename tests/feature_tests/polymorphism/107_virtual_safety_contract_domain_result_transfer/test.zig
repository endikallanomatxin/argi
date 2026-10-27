const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/107_virtual_safety_contract_domain_result_transfer" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/107_virtual_safety_contract_domain_result_transfer");
    try runExpect("tests/feature_tests/polymorphism/107_virtual_safety_contract_domain_result_transfer", 0);
}
