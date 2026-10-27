const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/56X_owned_handle_stale_capability" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/56X_owned_handle_stale_capability", "binding 'capability' was moved", "failed without a diagnostic");
}
