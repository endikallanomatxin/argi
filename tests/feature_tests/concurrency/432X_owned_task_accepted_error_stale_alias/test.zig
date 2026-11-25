const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "432X_owned_task_accepted_error_stale_alias" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/432X_owned_task_accepted_error_stale_alias", "reference depends on a root that has ended");
}
