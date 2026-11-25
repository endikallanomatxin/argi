const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "429X_owned_task_allocation_mutated_address" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/429X_owned_task_allocation_mutated_address", "task input lacks a static ownership-transfer guarantee");
}
