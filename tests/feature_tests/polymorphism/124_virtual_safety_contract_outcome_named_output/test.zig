const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/124_virtual_safety_contract_outcome_named_output" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/124_virtual_safety_contract_outcome_named_output");
    try runExpect("tests/feature_tests/polymorphism/124_virtual_safety_contract_outcome_named_output", 0);
}
