const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/46X_incomplete_construction" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/46X_incomplete_construction", "cannot be constructed", "failed without a diagnostic");
}
