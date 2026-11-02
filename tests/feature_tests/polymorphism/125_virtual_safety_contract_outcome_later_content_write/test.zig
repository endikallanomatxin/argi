const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/125_virtual_safety_contract_outcome_later_content_write" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/125_virtual_safety_contract_outcome_later_content_write");
    try runExpect("tests/feature_tests/polymorphism/125_virtual_safety_contract_outcome_later_content_write", 0);
}
