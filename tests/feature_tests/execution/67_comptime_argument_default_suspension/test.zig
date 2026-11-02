const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/67_comptime_argument_default_suspension" {
    try expectSuccessfulBuild("tests/feature_tests/execution/67_comptime_argument_default_suspension");
    try runExpect("tests/feature_tests/execution/67_comptime_argument_default_suspension", 42);
    try vmExpect("tests/feature_tests/execution/67_comptime_argument_default_suspension", 42, null);
}
