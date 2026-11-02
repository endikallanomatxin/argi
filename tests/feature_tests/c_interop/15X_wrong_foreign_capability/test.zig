const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/15X_wrong_foreign_capability" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/15X_wrong_foreign_capability", "ForeignFunctionInterface", "failed without a diagnostic");
}
