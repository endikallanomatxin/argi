const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/75X_callback_multiple_outputs" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/75X_callback_multiple_outputs", "must have zero or one output", "failed without a diagnostic");
}
