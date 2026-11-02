const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/98_virtual_safety_contract_outcome_dependencies" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/98_virtual_safety_contract_outcome_dependencies");
    try runExpect("tests/feature_tests/polymorphism/98_virtual_safety_contract_outcome_dependencies", 0);
}
