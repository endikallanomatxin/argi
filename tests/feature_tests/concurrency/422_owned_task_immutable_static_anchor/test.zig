const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "422_owned_task_immutable_static_anchor" {
    const path = "tests/feature_tests/concurrency/422_owned_task_immutable_static_anchor";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
