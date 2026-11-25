const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "441X_owned_task_array_local_sibling" {
    try support.expectFrontendFailure(
        "tests/feature_tests/concurrency/441X_owned_task_array_local_sibling",
        "task input lacks a static ownership-transfer guarantee",
    );
}
