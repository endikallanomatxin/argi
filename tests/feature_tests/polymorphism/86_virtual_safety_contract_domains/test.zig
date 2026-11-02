const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/86_virtual_safety_contract_domains" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/86_virtual_safety_contract_domains");
    try runExpect("tests/feature_tests/polymorphism/86_virtual_safety_contract_domains", 0);
}
