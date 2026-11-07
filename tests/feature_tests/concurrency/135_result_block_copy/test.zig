const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "native results copy initialized aligned representations across block boundaries" {
    const path = "tests/feature_tests/concurrency/135_result_block_copy";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
