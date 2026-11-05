const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 88X_delegated_virtual_receiver_conflict" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/88X_delegated_virtual_receiver_conflict", "concurrent access conflicts with a pending execution");
}
