const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "189_unknown_virtual_cleanup_after_reclaim" {
    const path = "tests/feature_tests/concurrency/189_unknown_virtual_cleanup_after_reclaim";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
