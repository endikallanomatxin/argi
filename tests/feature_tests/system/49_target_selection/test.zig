const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/49_target_selection" {
    const test_path = "tests/feature_tests/system/49_target_selection";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
