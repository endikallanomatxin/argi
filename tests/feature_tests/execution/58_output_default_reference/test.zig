const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/58_output_default_reference" {
    try expectSuccessfulBuild("tests/feature_tests/execution/58_output_default_reference");
    try runExpect("tests/feature_tests/execution/58_output_default_reference", 42);
    try vmExpect("tests/feature_tests/execution/58_output_default_reference", 42, null);
}
