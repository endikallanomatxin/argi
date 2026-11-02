const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/135_virtual_safety_contract_nested_owner_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/135_virtual_safety_contract_nested_owner_cleanup");
    try runExpect("tests/feature_tests/polymorphism/135_virtual_safety_contract_nested_owner_cleanup", 0);
}
