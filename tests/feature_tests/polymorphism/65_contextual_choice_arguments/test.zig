const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/65_contextual_choice_arguments" {
    const path = "tests/feature_tests/polymorphism/65_contextual_choice_arguments";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
