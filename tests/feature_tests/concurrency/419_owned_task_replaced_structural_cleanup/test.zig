const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "419_owned_task_replaced_structural_cleanup" {
    const path = "tests/feature_tests/concurrency/419_owned_task_replaced_structural_cleanup";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
