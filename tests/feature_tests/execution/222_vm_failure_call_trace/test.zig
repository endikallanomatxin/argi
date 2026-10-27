const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/222_vm_failure_call_trace" {
    try expectSuccessfulBuild("tests/feature_tests/execution/222_vm_failure_call_trace");
    try vmExpect("tests/feature_tests/execution/222_vm_failure_call_trace", 1, "ExecutionAborted");
    try vmExpect("tests/feature_tests/execution/222_vm_failure_call_trace", 1, "called from tests/feature_tests/execution/222_vm_failure_call_trace/main.rg:3:");
    try vmExpect("tests/feature_tests/execution/222_vm_failure_call_trace", 1, "called from tests/feature_tests/execution/222_vm_failure_call_trace/main.rg:5:");
}
