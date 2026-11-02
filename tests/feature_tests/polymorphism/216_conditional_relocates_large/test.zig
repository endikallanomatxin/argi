const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/216_conditional_relocates_large" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/216_conditional_relocates_large");
    try runExpect("tests/feature_tests/polymorphism/216_conditional_relocates_large", 0);
}
