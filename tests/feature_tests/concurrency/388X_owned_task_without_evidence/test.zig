const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;

test "388X_owned_task_without_evidence" {
    const path = "tests/feature_tests/concurrency/388X_owned_task_without_evidence";
    try support.expectFrontendFailure(path, "task input lacks a static ownership-transfer guarantee");
}
