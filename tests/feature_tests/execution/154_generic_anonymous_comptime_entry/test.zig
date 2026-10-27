const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/154_generic_anonymous_comptime_entry" {
    try expectSuccessfulBuild("tests/feature_tests/execution/154_generic_anonymous_comptime_entry");
    try runExpect("tests/feature_tests/execution/154_generic_anonymous_comptime_entry", 42);
    try vmExpect("tests/feature_tests/execution/154_generic_anonymous_comptime_entry", 42, null);
}
