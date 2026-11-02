const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/45X_incomplete_size" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/45X_incomplete_size", "has no size or alignment", "failed without a diagnostic");
}
