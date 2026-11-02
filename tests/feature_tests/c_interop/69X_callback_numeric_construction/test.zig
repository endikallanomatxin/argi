const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/69X_callback_numeric_construction" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/69X_callback_numeric_construction", "construction requires '.function = name'", "failed without a diagnostic");
}
