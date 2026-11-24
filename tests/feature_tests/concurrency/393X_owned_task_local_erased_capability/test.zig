const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "393X_owned_task_local_erased_capability" {
    const path = "tests/feature_tests/concurrency/393X_owned_task_local_erased_capability";
    try support.expectFrontendFailure(path, "task input lacks a static ownership-transfer guarantee");
}
