const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/158_concrete_selected_comptime_captures" {
    try expectSuccessfulBuild("tests/feature_tests/execution/158_concrete_selected_comptime_captures");
    try runExpect("tests/feature_tests/execution/158_concrete_selected_comptime_captures", 42);
    try vmExpect("tests/feature_tests/execution/158_concrete_selected_comptime_captures", 42, null);
}
