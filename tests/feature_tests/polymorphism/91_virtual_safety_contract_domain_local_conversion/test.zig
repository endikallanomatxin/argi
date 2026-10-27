const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/91_virtual_safety_contract_domain_local_conversion" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/91_virtual_safety_contract_domain_local_conversion");
    try runExpect("tests/feature_tests/polymorphism/91_virtual_safety_contract_domain_local_conversion", 0);
}
