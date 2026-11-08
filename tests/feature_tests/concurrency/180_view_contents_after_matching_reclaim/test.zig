const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "180_view_contents_after_matching_reclaim" {
    const path = "tests/feature_tests/concurrency/180_view_contents_after_matching_reclaim";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
