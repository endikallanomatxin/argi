const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "406X_owned_task_result_discard_cleanup" {
    const path = "tests/feature_tests/concurrency/406X_owned_task_result_discard_cleanup";
    try support.expectSuccessfulBuild(path);
    try support.runExpectFailure(path);
}
