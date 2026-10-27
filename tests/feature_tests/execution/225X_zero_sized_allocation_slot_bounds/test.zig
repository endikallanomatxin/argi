const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "tests/feature_tests/execution/225X_zero_sized_allocation_slot_bounds" {
    try expectSuccessfulBuild("tests/feature_tests/execution/225X_zero_sized_allocation_slot_bounds");
    try runExpectFailure("tests/feature_tests/execution/225X_zero_sized_allocation_slot_bounds");
    try vmExpect("tests/feature_tests/execution/225X_zero_sized_allocation_slot_bounds", 1, "ExecutionAborted");
}
