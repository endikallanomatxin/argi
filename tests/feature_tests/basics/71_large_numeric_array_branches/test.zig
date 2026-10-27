const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/71_large_numeric_array_branches" {
    const path = "tests/feature_tests/basics/71_large_numeric_array_branches";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
