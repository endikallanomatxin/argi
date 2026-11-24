const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "390_owned_task_cleanup_once" {
    const path = "tests/feature_tests/concurrency/390_owned_task_cleanup_once";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
