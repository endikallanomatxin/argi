const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/62_comptime_aggregate_projection" {
    try expectSuccessfulBuild("tests/feature_tests/execution/62_comptime_aggregate_projection");
    try runExpect("tests/feature_tests/execution/62_comptime_aggregate_projection", 42);
    try vmExpect("tests/feature_tests/execution/62_comptime_aggregate_projection", 42, null);
}
