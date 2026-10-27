const support = @import("../../../support.zig");
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/87X_vm_host_requires_binding" {
    try vmExpect("tests/feature_tests/execution/87X_vm_host_requires_binding", 1, "MissingHostBinding");
}
