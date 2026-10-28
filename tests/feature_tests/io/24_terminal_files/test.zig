const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/24_terminal_files" {
    const test_path = "tests/feature_tests/io/24_terminal_files";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
