const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/34_file_block_short_read" {
    const test_path = "tests/feature_tests/system/34_file_block_short_read";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
