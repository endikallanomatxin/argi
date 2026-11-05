const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 73X_access_before_call_completion" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/73X_access_before_call_completion", "concurrent access conflicts with a pending execution");
}
