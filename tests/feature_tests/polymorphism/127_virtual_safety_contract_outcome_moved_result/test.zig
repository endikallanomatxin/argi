const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/127_virtual_safety_contract_outcome_moved_result" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/127_virtual_safety_contract_outcome_moved_result");
    try runExpect("tests/feature_tests/polymorphism/127_virtual_safety_contract_outcome_moved_result", 0);
}
