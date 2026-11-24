const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "413_owned_task_retained_virtual_cleanup" {
    const path = "tests/feature_tests/concurrency/413_owned_task_retained_virtual_cleanup";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
