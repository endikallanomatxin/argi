const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/11_read_line_grows" {
    const test_path = "tests/feature_tests/io/11_read_line_grows";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
