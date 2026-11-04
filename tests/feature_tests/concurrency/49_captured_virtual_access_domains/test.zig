const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 49_captured_virtual_access_domains" {
    const path = "tests/feature_tests/concurrency/49_captured_virtual_access_domains";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
