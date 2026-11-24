const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "394X_owned_task_replaced_erased_capability" {
    const path = "tests/feature_tests/concurrency/394X_owned_task_replaced_erased_capability";
    try support.expectFrontendFailure(path, "task input lacks a static ownership-transfer guarantee");
}
