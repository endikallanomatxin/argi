const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/34_pipe_value_expressions" {
    const path = "tests/feature_tests/functions/34_pipe_value_expressions";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
