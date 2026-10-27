const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/09X_export_without_body" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/09X_export_without_body", "an exported CFunction requires a body", "failed without a diagnostic");
}
