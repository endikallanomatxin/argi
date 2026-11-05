const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 107_nested_virtual_access_argument" {
    const path = "tests/feature_tests/concurrency/107_nested_virtual_access_argument";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
