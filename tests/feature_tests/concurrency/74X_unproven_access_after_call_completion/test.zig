const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 74X_unproven_access_after_call_completion" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/74X_unproven_access_after_call_completion", "concurrent access conflicts with a pending execution");
}
