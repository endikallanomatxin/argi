const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/72X_callback_nominal_identity" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/72X_callback_nominal_identity", "no function named", "failed without a diagnostic");
}
