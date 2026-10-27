const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/141_projected_symbolic_independent_participant" {
    try expectSuccessfulBuild("tests/feature_tests/execution/141_projected_symbolic_independent_participant");
    try runExpect("tests/feature_tests/execution/141_projected_symbolic_independent_participant", 42);
    try vmExpect("tests/feature_tests/execution/141_projected_symbolic_independent_participant", 42, null);
}
