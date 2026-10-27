const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/10_pipe_generic_explicit" {
    const test_path = "tests/feature_tests/functions/10_pipe_generic_explicit";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}
