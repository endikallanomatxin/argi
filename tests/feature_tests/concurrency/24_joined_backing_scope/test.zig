const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 24_joined_backing_scope" {
    const path = "tests/feature_tests/concurrency/24_joined_backing_scope";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
