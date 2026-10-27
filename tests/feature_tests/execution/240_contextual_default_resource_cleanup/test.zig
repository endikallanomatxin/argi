const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/240_contextual_default_resource_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/execution/240_contextual_default_resource_cleanup");
    try runExpect("tests/feature_tests/execution/240_contextual_default_resource_cleanup", 42);
    try vmExpect("tests/feature_tests/execution/240_contextual_default_resource_cleanup", 42, null);
}
