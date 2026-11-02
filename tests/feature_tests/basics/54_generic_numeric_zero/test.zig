const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/54_generic_numeric_zero" {
    const path = "tests/feature_tests/basics/54_generic_numeric_zero";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
