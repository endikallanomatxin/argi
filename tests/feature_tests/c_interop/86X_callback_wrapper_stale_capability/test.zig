const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/86X_callback_wrapper_stale_capability" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/86X_callback_wrapper_stale_capability", "binding 'storage' was moved", "failed without a diagnostic");
}
