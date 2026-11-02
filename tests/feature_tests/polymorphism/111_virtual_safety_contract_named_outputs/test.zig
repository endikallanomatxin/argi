const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/111_virtual_safety_contract_named_outputs" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/111_virtual_safety_contract_named_outputs");
    try runExpect("tests/feature_tests/polymorphism/111_virtual_safety_contract_named_outputs", 0);
}
