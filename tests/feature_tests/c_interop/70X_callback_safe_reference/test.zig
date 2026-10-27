const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/70X_callback_safe_reference" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/70X_callback_safe_reference", "parameters require RawPointer", "failed without a diagnostic");
}
