const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/18_cleanup_vm" {
    try expectSuccessfulBuild("tests/feature_tests/execution/18_cleanup_vm");
    try runExpect("tests/feature_tests/execution/18_cleanup_vm", 42);
    try vmExpect("tests/feature_tests/execution/18_cleanup_vm", 42, null);
}
