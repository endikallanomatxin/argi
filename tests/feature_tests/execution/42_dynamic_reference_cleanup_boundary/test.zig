const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/42_dynamic_reference_cleanup_boundary" {
    try expectSuccessfulBuild("tests/feature_tests/execution/42_dynamic_reference_cleanup_boundary");
    try runExpect("tests/feature_tests/execution/42_dynamic_reference_cleanup_boundary", 0);
    try vmExpect("tests/feature_tests/execution/42_dynamic_reference_cleanup_boundary", 0, null);
}
