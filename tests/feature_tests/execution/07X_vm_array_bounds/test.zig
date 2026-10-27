const support = @import("../../../support.zig");
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/07X_vm_array_bounds" {
    try vmExpect("tests/feature_tests/execution/07X_vm_array_bounds", 1, "ExecutionIndexOutOfBounds");
}
