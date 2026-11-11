const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "205X_conditional_reference_retarget_pending_writer" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/205X_conditional_reference_retarget_pending_writer", "pending execution");
}
