const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectStdout = support.runExpectStdout;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/36_entry_flushes_stdout" {
    const test_path = "tests/feature_tests/system/36_entry_flushes_stdout";
    try expectSuccessfulBuild(test_path);
    try runExpectStdout(test_path, 0, "A");
}
