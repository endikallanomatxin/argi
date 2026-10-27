const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/64_comptime_specialization_arguments" {
    try expectSuccessfulBuild("tests/feature_tests/execution/64_comptime_specialization_arguments");
    try runExpect("tests/feature_tests/execution/64_comptime_specialization_arguments", 42);
    try vmExpect("tests/feature_tests/execution/64_comptime_specialization_arguments", 42, null);
}
