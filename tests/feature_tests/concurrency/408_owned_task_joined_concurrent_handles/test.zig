const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "408_owned_task_joined_concurrent_handles" {
    const path = "tests/feature_tests/concurrency/408_owned_task_joined_concurrent_handles";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
