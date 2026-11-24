const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "423X_owned_task_mutable_static_anchor" {
    const path = "tests/feature_tests/concurrency/423X_owned_task_mutable_static_anchor";
    try support.expectFrontendFailure(path, "task input lacks a static ownership-transfer guarantee");
}
