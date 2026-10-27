const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/155_nested_comptime_capture_context" {
    try expectSuccessfulBuild("tests/feature_tests/execution/155_nested_comptime_capture_context");
    try runExpect("tests/feature_tests/execution/155_nested_comptime_capture_context", 42);
    try vmExpect("tests/feature_tests/execution/155_nested_comptime_capture_context", 42, null);
}
