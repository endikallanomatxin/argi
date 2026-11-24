const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "404_owned_task_owned_result" {
    const path = "tests/feature_tests/concurrency/404_owned_task_owned_result";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
