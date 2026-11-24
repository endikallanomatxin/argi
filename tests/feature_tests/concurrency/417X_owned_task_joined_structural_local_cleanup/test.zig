const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "417X_owned_task_joined_structural_local_cleanup" {
    const path = "tests/feature_tests/concurrency/417X_owned_task_joined_structural_local_cleanup";
    try support.expectFrontendFailure(path, "task input lacks a static ownership-transfer guarantee");
}
