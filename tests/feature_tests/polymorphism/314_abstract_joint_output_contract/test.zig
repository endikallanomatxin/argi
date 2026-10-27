const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/314_abstract_joint_output_contract" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/314_abstract_joint_output_contract");
    try runExpect("tests/feature_tests/polymorphism/314_abstract_joint_output_contract", 0);
}
