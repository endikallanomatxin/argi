const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/318_abstract_joint_output_copied_selectors" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/318_abstract_joint_output_copied_selectors");
    try runExpect("tests/feature_tests/polymorphism/318_abstract_joint_output_copied_selectors", 0);
}
