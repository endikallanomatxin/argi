const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/84_numeric_byte_views_vm" {
    try expectSuccessfulBuild("tests/feature_tests/execution/84_numeric_byte_views_vm");
    try runExpect("tests/feature_tests/execution/84_numeric_byte_views_vm", 42);
    try vmExpect("tests/feature_tests/execution/84_numeric_byte_views_vm", 42, null);
}
