const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 31_virtual_access_bounds" {
    const path = "tests/feature_tests/concurrency/31_virtual_access_bounds";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
