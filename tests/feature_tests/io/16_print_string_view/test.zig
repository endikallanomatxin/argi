const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectStdout = support.runExpectStdout;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/16_print_string_view" {
    const test_path = "tests/feature_tests/io/16_print_string_view";
    try expectSuccessfulBuild(test_path);
    try runExpectStdout(test_path, 0, "string view output\n");
}
