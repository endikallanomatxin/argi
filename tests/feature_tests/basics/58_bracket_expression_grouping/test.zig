const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/58_bracket_expression_grouping" {
    const path = "tests/feature_tests/basics/58_bracket_expression_grouping";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
