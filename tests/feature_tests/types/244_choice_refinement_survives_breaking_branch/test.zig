const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/244_choice_refinement_survives_breaking_branch" {
    const test_path = "tests/feature_tests/types/244_choice_refinement_survives_breaking_branch";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
