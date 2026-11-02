const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/277_specialized_comparison_assumed_input" {
    const path = "tests/feature_tests/types/277_specialized_comparison_assumed_input";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
