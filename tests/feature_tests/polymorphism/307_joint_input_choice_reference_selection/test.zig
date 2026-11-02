const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/307_joint_input_choice_reference_selection" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/307_joint_input_choice_reference_selection");
    try runExpect("tests/feature_tests/polymorphism/307_joint_input_choice_reference_selection", 0);
}
