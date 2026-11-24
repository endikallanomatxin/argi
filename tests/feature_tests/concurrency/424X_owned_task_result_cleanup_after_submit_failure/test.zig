const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "424X_owned_task_result_cleanup_after_submit_failure" {
    const path = "tests/feature_tests/concurrency/424X_owned_task_result_cleanup_after_submit_failure";
    try support.expectSuccessfulBuild(path);
    try support.runExpectFailure(path);
}
