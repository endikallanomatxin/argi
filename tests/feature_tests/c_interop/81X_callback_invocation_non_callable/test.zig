const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/81X_callback_invocation_non_callable" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/81X_callback_invocation_non_callable", "expected a CFunctionPointer value", "failed without a diagnostic");
}
