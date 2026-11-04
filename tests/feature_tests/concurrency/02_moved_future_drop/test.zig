const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 02_moved_future_drop" {
    const path = "tests/feature_tests/concurrency/02_moved_future_drop";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
