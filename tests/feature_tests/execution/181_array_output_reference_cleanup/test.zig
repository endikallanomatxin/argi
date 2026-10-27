const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/181_array_output_reference_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/execution/181_array_output_reference_cleanup");
    try runExpect("tests/feature_tests/execution/181_array_output_reference_cleanup", 42);
    try vmExpect("tests/feature_tests/execution/181_array_output_reference_cleanup", 42, null);
}
