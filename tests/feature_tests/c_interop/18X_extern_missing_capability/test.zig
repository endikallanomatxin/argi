const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/18X_extern_missing_capability" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/18X_extern_missing_capability", ".ffi: $&ForeignFunctionInterface", "failed without a diagnostic");
}
