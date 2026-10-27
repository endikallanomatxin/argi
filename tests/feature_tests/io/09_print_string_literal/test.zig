const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectStdout = support.runExpectStdout;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/09_print_string_literal" {
    const test_path = "tests/feature_tests/io/09_print_string_literal";
    try expectSuccessfulBuild(test_path);
    try runExpectStdout(test_path, 0, "literal output\n");
}
