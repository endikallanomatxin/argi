const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/171_array_view_iteration" {
    const path = "tests/feature_tests/collections/171_array_view_iteration";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
