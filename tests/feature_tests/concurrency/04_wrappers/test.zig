const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 04_wrappers" {
    const path = "tests/feature_tests/concurrency/04_wrappers";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
