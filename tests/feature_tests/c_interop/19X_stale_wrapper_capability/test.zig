const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/19X_stale_wrapper_capability" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/19X_stale_wrapper_capability", "binding 'storage' was moved", "failed without a diagnostic");
}
