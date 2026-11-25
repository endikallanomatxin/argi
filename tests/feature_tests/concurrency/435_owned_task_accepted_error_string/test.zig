const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "435_owned_task_accepted_error_string" {
    const path = "tests/feature_tests/concurrency/435_owned_task_accepted_error_string";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
