const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/147_symbolic_reinitialization_independent" {
    try expectSuccessfulBuild("tests/feature_tests/execution/147_symbolic_reinitialization_independent");
    try runExpect("tests/feature_tests/execution/147_symbolic_reinitialization_independent", 42);
    try vmExpect("tests/feature_tests/execution/147_symbolic_reinitialization_independent", 42, null);
}
