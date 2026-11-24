const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;

test "387_owned_task_nominal" {
    const path = "tests/feature_tests/concurrency/387_owned_task_nominal";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
