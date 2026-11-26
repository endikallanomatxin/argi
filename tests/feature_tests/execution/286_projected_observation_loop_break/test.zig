const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/286_projected_observation_loop_break" {
    const path = "tests/feature_tests/execution/286_projected_observation_loop_break";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
