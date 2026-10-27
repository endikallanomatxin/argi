const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/117_acquired_memory_boundary" {
    try expectSuccessfulBuild("tests/feature_tests/execution/117_acquired_memory_boundary");
    try runExpect("tests/feature_tests/execution/117_acquired_memory_boundary", 42);
    try vmExpect("tests/feature_tests/execution/117_acquired_memory_boundary", 42, null);
}
