const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/419_virtual_construction" {
    const path = "tests/feature_tests/types/419_virtual_construction";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
