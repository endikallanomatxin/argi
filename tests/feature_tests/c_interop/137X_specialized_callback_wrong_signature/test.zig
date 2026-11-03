const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "137X_specialized_callback_wrong_signature" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/137X_specialized_callback_wrong_signature", "no visible concrete CFunction body matches the callback signature", "failed without a diagnostic");
}
