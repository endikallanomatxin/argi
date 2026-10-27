const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/49X_incomplete_safe_reference" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/49X_incomplete_safe_reference", "cannot form a safe reference", "failed without a diagnostic");
}
