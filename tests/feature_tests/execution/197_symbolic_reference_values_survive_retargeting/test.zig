const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/197_symbolic_reference_values_survive_retargeting" {
    try expectSuccessfulBuild("tests/feature_tests/execution/197_symbolic_reference_values_survive_retargeting");
    try runExpect("tests/feature_tests/execution/197_symbolic_reference_values_survive_retargeting", 42);
    try vmExpect("tests/feature_tests/execution/197_symbolic_reference_values_survive_retargeting", 42, null);
}
