const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/53_comptime_argument_calls" {
    try expectSuccessfulBuild("tests/feature_tests/execution/53_comptime_argument_calls");
    try runExpect("tests/feature_tests/execution/53_comptime_argument_calls", 42);
    try vmExpect("tests/feature_tests/execution/53_comptime_argument_calls", 42, null);
}
