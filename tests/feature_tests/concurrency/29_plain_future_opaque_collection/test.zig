const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 29_plain_future_opaque_collection" {
    const path = "tests/feature_tests/concurrency/29_plain_future_opaque_collection";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
