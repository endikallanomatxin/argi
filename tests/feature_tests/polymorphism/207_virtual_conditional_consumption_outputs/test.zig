const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/207_virtual_conditional_consumption_outputs" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/207_virtual_conditional_consumption_outputs");
    try runExpect("tests/feature_tests/polymorphism/207_virtual_conditional_consumption_outputs", 0);
}
