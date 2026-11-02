const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/75_virtual_safety_contract_associated" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/75_virtual_safety_contract_associated");
    try runExpect("tests/feature_tests/polymorphism/75_virtual_safety_contract_associated", 0);
}
