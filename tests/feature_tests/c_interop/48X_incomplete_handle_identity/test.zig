const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/48X_incomplete_handle_identity" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/48X_incomplete_handle_identity", "no function named '_read' accepts arguments", "failed without a diagnostic");
}
