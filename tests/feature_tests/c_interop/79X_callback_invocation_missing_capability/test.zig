const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/79X_callback_invocation_missing_capability" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/79X_callback_invocation_missing_capability", "arguments do not match the C callback signature", "failed without a diagnostic");
}
