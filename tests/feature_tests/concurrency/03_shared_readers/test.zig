const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 03_shared_readers" {
    const path = "tests/feature_tests/concurrency/03_shared_readers";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
