const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "434_owned_task_accepted_error_allocation" {
    const path = "tests/feature_tests/concurrency/434_owned_task_accepted_error_allocation";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
