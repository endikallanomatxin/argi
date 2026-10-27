const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/153_anonymous_comptime_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/execution/153_anonymous_comptime_cleanup");
    try runExpect("tests/feature_tests/execution/153_anonymous_comptime_cleanup", 42);
    try vmExpect("tests/feature_tests/execution/153_anonymous_comptime_cleanup", 42, null);
}
