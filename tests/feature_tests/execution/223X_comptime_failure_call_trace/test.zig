const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/223X_comptime_failure_call_trace" {
    try buildExpectFail("tests/feature_tests/execution/223X_comptime_failure_call_trace", "#run evaluation aborted");
    try buildExpectFail("tests/feature_tests/execution/223X_comptime_failure_call_trace", "called from tests/feature_tests/execution/223X_comptime_failure_call_trace/main.rg:3:");
    try vmExpect("tests/feature_tests/execution/223X_comptime_failure_call_trace", 1, "called from");
}
