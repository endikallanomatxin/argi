const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "428X_owned_task_allocation_stale_alias" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/428X_owned_task_allocation_stale_alias", "reference depends on a root that has ended");
}
