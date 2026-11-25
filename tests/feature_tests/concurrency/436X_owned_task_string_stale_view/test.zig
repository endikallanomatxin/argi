const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "436X_owned_task_string_stale_view" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/436X_owned_task_string_stale_view", "reference depends on a root that has ended");
}
