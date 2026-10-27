const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/33_retargetable_alias_vm_boundary" {
    try expectSuccessfulBuild("tests/feature_tests/execution/33_retargetable_alias_vm_boundary");
    try runExpect("tests/feature_tests/execution/33_retargetable_alias_vm_boundary", 0);
    try vmExpect("tests/feature_tests/execution/33_retargetable_alias_vm_boundary", 0, null);
}
