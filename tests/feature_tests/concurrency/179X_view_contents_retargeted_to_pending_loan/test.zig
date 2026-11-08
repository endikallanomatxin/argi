const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "179X_view_contents_retargeted_to_pending_loan" {
    try support.expectFrontendFailure(
        "tests/feature_tests/concurrency/179X_view_contents_retargeted_to_pending_loan",
        "pending execution",
    );
}
