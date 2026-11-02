const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/82_virtual_safety_contract_invalidate_input" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/82_virtual_safety_contract_invalidate_input");
    try runExpect("tests/feature_tests/polymorphism/82_virtual_safety_contract_invalidate_input", 0);
}
