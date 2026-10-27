const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectStdout = support.runExpectStdout;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/28_buffered_terminal_output" {
    const test_path = "tests/feature_tests/io/28_buffered_terminal_output";
    try expectSuccessfulBuild(test_path);
    try runExpectStdout(test_path, 0, "Buffered output\nOK");
}
