const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/329_generic_choice_comparison" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/329_generic_choice_comparison");
    try runExpect("tests/feature_tests/polymorphism/329_generic_choice_comparison", 0);
}
