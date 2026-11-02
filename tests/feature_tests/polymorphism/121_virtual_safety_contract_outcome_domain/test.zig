const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/121_virtual_safety_contract_outcome_domain" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/121_virtual_safety_contract_outcome_domain");
    try runExpect("tests/feature_tests/polymorphism/121_virtual_safety_contract_outcome_domain", 0);
}
