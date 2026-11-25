const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "433_owned_task_string" {
    const path = "tests/feature_tests/concurrency/433_owned_task_string";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
