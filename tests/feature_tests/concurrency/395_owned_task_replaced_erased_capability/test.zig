const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "395_owned_task_replaced_erased_capability" {
    const path = "tests/feature_tests/concurrency/395_owned_task_replaced_erased_capability";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
