const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/23_terminal_abort" {
    const test_path = "tests/feature_tests/basics/23_terminal_abort";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}
