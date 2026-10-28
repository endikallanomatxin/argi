const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/05_buffered_file_wrappers" {
    const test_path = "tests/feature_tests/io/05_buffered_file_wrappers";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
