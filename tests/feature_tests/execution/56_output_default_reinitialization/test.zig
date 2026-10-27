const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/56_output_default_reinitialization" {
    try expectSuccessfulBuild("tests/feature_tests/execution/56_output_default_reinitialization");
    try runExpect("tests/feature_tests/execution/56_output_default_reinitialization", 42);
    try vmExpect("tests/feature_tests/execution/56_output_default_reinitialization", 42, null);
}
