const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/50X_incomplete_alignment" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/50X_incomplete_alignment", "has no size or alignment", "failed without a diagnostic");
}
