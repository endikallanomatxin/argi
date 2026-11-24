const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "425_owned_task_result_cleanup_once" {
    const path = "tests/feature_tests/concurrency/425_owned_task_result_cleanup_once";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
