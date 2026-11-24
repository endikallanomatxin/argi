const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "391X_owned_task_choice_loan" {
    const path = "tests/feature_tests/concurrency/391X_owned_task_choice_loan";
    try support.expectFrontendFailure(path, "concurrent access conflicts with a pending execution");
}
