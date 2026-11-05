const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 160X_callback_access_global" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/160X_callback_access_global", "callback body violates its declared access bounds");
}
