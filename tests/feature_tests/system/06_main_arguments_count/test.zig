const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/06_main_arguments_count" {
    const test_path = "tests/feature_tests/system/06_main_arguments_count";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
