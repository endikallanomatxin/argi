const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 48_static_captured_access_bound" {
    const path = "tests/feature_tests/concurrency/48_static_captured_access_bound";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
