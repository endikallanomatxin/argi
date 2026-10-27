const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/10X_export_aggregate" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/10X_export_aggregate", "input 'value' has an unsupported C ABI type", "failed without a diagnostic");
}
