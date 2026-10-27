const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/145_projected_observation_args_independent" {
    try expectSuccessfulBuild("tests/feature_tests/execution/145_projected_observation_args_independent");
    try runExpect("tests/feature_tests/execution/145_projected_observation_args_independent", 42);
    try vmExpect("tests/feature_tests/execution/145_projected_observation_args_independent", 42, null);
}
