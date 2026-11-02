const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/71_virtual_safety_contract_preservation" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/71_virtual_safety_contract_preservation");
    try runExpect("tests/feature_tests/polymorphism/71_virtual_safety_contract_preservation", 0);
}
