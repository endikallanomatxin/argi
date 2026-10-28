const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/07_file_open_close" {
    const test_path = "tests/feature_tests/io/07_file_open_close";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
