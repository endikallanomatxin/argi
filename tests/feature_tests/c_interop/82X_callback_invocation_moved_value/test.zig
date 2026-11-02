const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/82X_callback_invocation_moved_value" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/82X_callback_invocation_moved_value", "binding 'callback' was moved", "failed without a diagnostic");
}
