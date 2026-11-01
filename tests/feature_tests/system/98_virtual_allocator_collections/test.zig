const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/98_virtual_allocator_collections" {
    const path = "tests/feature_tests/system/98_virtual_allocator_collections";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
