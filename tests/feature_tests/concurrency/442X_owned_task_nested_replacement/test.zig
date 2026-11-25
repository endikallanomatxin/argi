const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "442X_owned_task_nested_replacement" {
    const path = "tests/feature_tests/concurrency/442X_owned_task_nested_replacement";
    try support.expectFrontendFailure(path, "task input lacks a static ownership-transfer guarantee");
}
