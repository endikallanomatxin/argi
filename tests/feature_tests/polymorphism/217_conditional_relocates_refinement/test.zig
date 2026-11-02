const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/217_conditional_relocates_refinement" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/217_conditional_relocates_refinement");
    try runExpect("tests/feature_tests/polymorphism/217_conditional_relocates_refinement", 0);
}
