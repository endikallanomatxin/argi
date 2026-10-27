const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/134_virtual_safety_contract_nested_common" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/134_virtual_safety_contract_nested_common");
    try runExpect("tests/feature_tests/polymorphism/134_virtual_safety_contract_nested_common", 0);
}
