const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/93_virtual_safety_contract_domain_sibling" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/93_virtual_safety_contract_domain_sibling");
    try runExpect("tests/feature_tests/polymorphism/93_virtual_safety_contract_domain_sibling", 0);
}
