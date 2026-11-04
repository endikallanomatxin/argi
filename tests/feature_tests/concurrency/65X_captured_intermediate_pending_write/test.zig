const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 65X_captured_intermediate_pending_write" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/65X_captured_intermediate_pending_write", "pending execution");
}
