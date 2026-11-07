const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "148_result_copy_with_pending_writer" {
    const path = "tests/feature_tests/concurrency/148_result_copy_with_pending_writer";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
