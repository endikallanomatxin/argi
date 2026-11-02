const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/320_abstract_joint_output_forwarding" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/320_abstract_joint_output_forwarding");
    try runExpect("tests/feature_tests/polymorphism/320_abstract_joint_output_forwarding", 0);
}
