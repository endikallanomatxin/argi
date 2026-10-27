const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/68_virtual_safety_contract" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/68_virtual_safety_contract");
    try runExpect("tests/feature_tests/polymorphism/68_virtual_safety_contract", 0);
}
