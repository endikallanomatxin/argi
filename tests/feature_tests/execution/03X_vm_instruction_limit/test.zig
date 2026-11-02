const support = @import("../../../support.zig");
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/03X_vm_instruction_limit" {
    try vmExpect("tests/feature_tests/execution/03X_vm_instruction_limit", 1, "ExecutionInstructionLimit");
}
