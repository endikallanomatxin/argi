const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/143_projected_observation_forwarding" {
    try expectSuccessfulBuild("tests/feature_tests/execution/143_projected_observation_forwarding");
    try runExpect("tests/feature_tests/execution/143_projected_observation_forwarding", 42);
    try vmExpect("tests/feature_tests/execution/143_projected_observation_forwarding", 42, null);
}
