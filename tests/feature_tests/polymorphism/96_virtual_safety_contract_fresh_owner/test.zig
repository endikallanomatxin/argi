const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/96_virtual_safety_contract_fresh_owner" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/96_virtual_safety_contract_fresh_owner");
    try runExpect("tests/feature_tests/polymorphism/96_virtual_safety_contract_fresh_owner", 0);
}
