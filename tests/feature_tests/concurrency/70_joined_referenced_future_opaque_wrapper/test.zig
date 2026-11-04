const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 70_joined_referenced_future_opaque_wrapper" {
    const path = "tests/feature_tests/concurrency/70_joined_referenced_future_opaque_wrapper";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
