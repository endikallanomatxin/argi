const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/78_virtual_safety_contract_referent" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/78_virtual_safety_contract_referent");
    try runExpect("tests/feature_tests/polymorphism/78_virtual_safety_contract_referent", 0);
}
