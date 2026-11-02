const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/27_buffered_writer_policy" {
    const test_path = "tests/feature_tests/io/27_buffered_writer_policy";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
