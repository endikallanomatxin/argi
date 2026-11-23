const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "325_shared_readers_allow_cleanup_after_both_joins" {
    const path = "tests/feature_tests/concurrency/325_shared_readers_allow_cleanup_after_both_joins";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
