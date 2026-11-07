const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "143_late_virtual_collection_after_completion" {
    const path = "tests/feature_tests/concurrency/143_late_virtual_collection_after_completion";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
