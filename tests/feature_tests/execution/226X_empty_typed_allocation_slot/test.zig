const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/execution/226X_empty_typed_allocation_slot" {
    try expectSuccessfulBuild("tests/feature_tests/execution/226X_empty_typed_allocation_slot");
    try runExpectFailure("tests/feature_tests/execution/226X_empty_typed_allocation_slot");
    try vmExpect("tests/feature_tests/execution/226X_empty_typed_allocation_slot", 1, "ExecutionAborted");
}
