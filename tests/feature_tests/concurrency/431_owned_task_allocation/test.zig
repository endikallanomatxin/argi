const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "431_owned_task_allocation" {
    const path = "tests/feature_tests/concurrency/431_owned_task_allocation";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
