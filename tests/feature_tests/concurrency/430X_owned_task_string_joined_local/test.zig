const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "430X_owned_task_string_joined_local" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/430X_owned_task_string_joined_local", "task input lacks a static ownership-transfer guarantee");
}
