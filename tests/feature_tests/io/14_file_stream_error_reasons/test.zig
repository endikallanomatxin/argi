const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/14_file_stream_error_reasons" {
    const test_path = "tests/feature_tests/io/14_file_stream_error_reasons";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
