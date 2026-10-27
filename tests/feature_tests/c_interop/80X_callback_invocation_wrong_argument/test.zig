const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/80X_callback_invocation_wrong_argument" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/80X_callback_invocation_wrong_argument", "arguments do not match the C callback signature", "failed without a diagnostic");
}
