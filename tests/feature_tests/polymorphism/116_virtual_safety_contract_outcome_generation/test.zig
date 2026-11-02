const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/116_virtual_safety_contract_outcome_generation" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/116_virtual_safety_contract_outcome_generation");
    try runExpect("tests/feature_tests/polymorphism/116_virtual_safety_contract_outcome_generation", 0);
}
