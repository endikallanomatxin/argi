const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/execution/227X_unreserved_zero_sized_slot" {
    try expectSuccessfulBuild("tests/feature_tests/execution/227X_unreserved_zero_sized_slot");
    try runExpectFailure("tests/feature_tests/execution/227X_unreserved_zero_sized_slot");
    try vmExpect("tests/feature_tests/execution/227X_unreserved_zero_sized_slot", 1, "ExecutionAborted");
}
