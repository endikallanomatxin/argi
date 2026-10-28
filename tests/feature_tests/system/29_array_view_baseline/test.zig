const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/29_array_view_baseline" {
    const test_path = "tests/feature_tests/system/29_array_view_baseline";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 12);
}
