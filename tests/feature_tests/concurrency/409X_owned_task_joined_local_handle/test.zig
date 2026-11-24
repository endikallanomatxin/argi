const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "409X_owned_task_joined_local_handle" {
    const path = "tests/feature_tests/concurrency/409X_owned_task_joined_local_handle";
    try support.expectFrontendFailure(path, "task input lacks a static ownership-transfer guarantee");
}
