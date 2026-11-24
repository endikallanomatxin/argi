const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "412_owned_task_result_virtual_cleanup" {
    const path = "tests/feature_tests/concurrency/412_owned_task_result_virtual_cleanup";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
