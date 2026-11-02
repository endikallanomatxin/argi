const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/322_abstract_joint_input_choices" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/322_abstract_joint_input_choices");
    try runExpect("tests/feature_tests/polymorphism/322_abstract_joint_input_choices", 0);
}
