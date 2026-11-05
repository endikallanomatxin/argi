const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 161X_callback_access_unknown_storage" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/161X_callback_access_unknown_storage", "callback body violates its declared access bounds");
}
