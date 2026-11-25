const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "440_owned_task_array_capability_replacement" {
    const path = "tests/feature_tests/concurrency/440_owned_task_array_capability_replacement";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
