const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "194X_retyped_source_retargeted_before_return" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/194X_retyped_source_retargeted_before_return", "pending execution");
}
