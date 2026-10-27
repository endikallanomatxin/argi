const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/200_virtual_conditional_consumption" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/200_virtual_conditional_consumption");
    try runExpect("tests/feature_tests/polymorphism/200_virtual_conditional_consumption", 0);
}
