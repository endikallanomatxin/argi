const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "418X_owned_task_replaced_structural_cleanup" {
    const path = "tests/feature_tests/concurrency/418X_owned_task_replaced_structural_cleanup";
    try support.expectFrontendFailure(path, "task input lacks a static ownership-transfer guarantee");
}
