const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/72_virtual_safety_contract_block" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/72_virtual_safety_contract_block");
    try runExpect("tests/feature_tests/polymorphism/72_virtual_safety_contract_block", 0);
}
