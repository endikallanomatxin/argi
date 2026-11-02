const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/14_file_system_capability" {
    const test_path = "tests/feature_tests/system/14_file_system_capability";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
