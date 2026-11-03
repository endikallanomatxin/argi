const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "specialized callback invocation requires ffi" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/135X_specialized_callback_missing_capability", "arguments do not match the C callback signature", "failed without a diagnostic");
}
