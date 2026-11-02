const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/55X_owned_handle_after_cleanup" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/55X_owned_handle_after_cleanup", "reference depends on a root that has ended", "failed without a diagnostic");
}
