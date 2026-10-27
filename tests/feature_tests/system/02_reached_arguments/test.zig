const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/02_reached_arguments" {
    const test_path = "tests/feature_tests/system/02_reached_arguments";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 9);
}
