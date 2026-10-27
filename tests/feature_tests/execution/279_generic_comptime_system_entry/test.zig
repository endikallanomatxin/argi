const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/279_generic_comptime_system_entry" {
    try expectSuccessfulBuild("tests/feature_tests/execution/279_generic_comptime_system_entry");
    try runExpect("tests/feature_tests/execution/279_generic_comptime_system_entry", 42);
    try vmExpect("tests/feature_tests/execution/279_generic_comptime_system_entry", 42, null);
}
