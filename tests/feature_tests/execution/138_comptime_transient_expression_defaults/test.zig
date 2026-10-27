const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/138_comptime_transient_expression_defaults" {
    try expectSuccessfulBuild("tests/feature_tests/execution/138_comptime_transient_expression_defaults");
    try runExpect("tests/feature_tests/execution/138_comptime_transient_expression_defaults", 42);
    try vmExpect("tests/feature_tests/execution/138_comptime_transient_expression_defaults", 42, null);
}
