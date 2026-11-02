const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/82_fallible_main_explicit" {
    const path = "tests/feature_tests/basics/82_fallible_main_explicit";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
