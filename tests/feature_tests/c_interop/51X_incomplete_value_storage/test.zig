const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/51X_incomplete_value_storage" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/51X_incomplete_value_storage", "has no value representation", "failed without a diagnostic");
}
