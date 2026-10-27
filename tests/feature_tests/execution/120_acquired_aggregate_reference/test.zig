const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/120_acquired_aggregate_reference" {
    try expectSuccessfulBuild("tests/feature_tests/execution/120_acquired_aggregate_reference");
    try runExpect("tests/feature_tests/execution/120_acquired_aggregate_reference", 42);
    try vmExpect("tests/feature_tests/execution/120_acquired_aggregate_reference", 42, null);
}
