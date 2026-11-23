const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "328X_cleanup_after_partial_branch_join" {
    try support.expectFrontendFailure(
        "tests/feature_tests/concurrency/328X_cleanup_after_partial_branch_join",
        "concurrent access conflicts with a pending execution",
    );
}
