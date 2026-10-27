const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/168_acquired_logical_slot" {
    try expectSuccessfulBuild("tests/feature_tests/execution/168_acquired_logical_slot");
    try runExpect("tests/feature_tests/execution/168_acquired_logical_slot", 42);
    try vmExpect("tests/feature_tests/execution/168_acquired_logical_slot", 42, null);
}
