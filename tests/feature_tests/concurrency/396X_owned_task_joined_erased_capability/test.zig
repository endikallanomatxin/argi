const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "396X_owned_task_joined_erased_capability" {
    const path = "tests/feature_tests/concurrency/396X_owned_task_joined_erased_capability";
    try support.expectFrontendFailure(path, "task input lacks a static ownership-transfer guarantee");
}
