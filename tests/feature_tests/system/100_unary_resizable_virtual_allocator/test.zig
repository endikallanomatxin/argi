const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/100_unary_resizable_virtual_allocator" {
    const path = "tests/feature_tests/system/100_unary_resizable_virtual_allocator";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
