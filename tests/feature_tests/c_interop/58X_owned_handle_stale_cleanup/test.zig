const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/58X_owned_handle_stale_cleanup" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/58X_owned_handle_stale_cleanup", "binding 'capability' was moved", "failed without a diagnostic");
}
