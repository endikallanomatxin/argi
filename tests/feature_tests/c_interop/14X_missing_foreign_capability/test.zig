const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/14X_missing_foreign_capability" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/14X_missing_foreign_capability", ".ffi: $&ForeignFunctionInterface", "failed without a diagnostic");
}
