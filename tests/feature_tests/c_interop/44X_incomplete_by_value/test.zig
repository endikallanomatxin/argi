const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/44X_incomplete_by_value" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/44X_incomplete_by_value", "has no value representation", "failed without a diagnostic");
}
