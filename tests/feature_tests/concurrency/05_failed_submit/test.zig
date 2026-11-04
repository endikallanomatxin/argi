const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 05_failed_submit" {
    const path = "tests/feature_tests/concurrency/05_failed_submit";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
