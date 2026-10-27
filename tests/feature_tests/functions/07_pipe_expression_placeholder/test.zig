const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/07_pipe_expression_placeholder" {
    const path = "tests/feature_tests/functions/07_pipe_expression_placeholder";
    try expectSuccessfulBuild(path);
    try runExpect(path, 42);
}
