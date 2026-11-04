const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 18_borrowed_fixed_arrays" {
    const path = "tests/feature_tests/concurrency/18_borrowed_fixed_arrays";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
