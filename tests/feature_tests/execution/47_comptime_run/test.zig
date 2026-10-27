const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/47_comptime_run" {
    try expectSuccessfulBuild("tests/feature_tests/execution/47_comptime_run");
    try runExpect("tests/feature_tests/execution/47_comptime_run", 42);
    try vmExpect("tests/feature_tests/execution/47_comptime_run", 42, null);
}
