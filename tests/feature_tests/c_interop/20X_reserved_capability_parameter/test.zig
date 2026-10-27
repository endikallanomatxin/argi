const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/20X_reserved_capability_parameter" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/20X_reserved_capability_parameter", "reserve '.ffi' for the checked capability", "failed without a diagnostic");
}
