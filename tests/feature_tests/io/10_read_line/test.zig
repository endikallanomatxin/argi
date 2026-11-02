const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/10_read_line" {
    const test_path = "tests/feature_tests/io/10_read_line";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
