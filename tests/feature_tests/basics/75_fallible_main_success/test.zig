const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/75_fallible_main_success" {
    const path = "tests/feature_tests/basics/75_fallible_main_success";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
