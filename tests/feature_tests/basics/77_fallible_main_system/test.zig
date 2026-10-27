const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectStdoutWithArgs = support.runExpectStdoutWithArgs;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/77_fallible_main_system" {
    const path = "tests/feature_tests/basics/77_fallible_main_system";
    try expectSuccessfulBuild(path);
    try runExpectStdoutWithArgs(path, &.{}, 0, "ready\n");
}
