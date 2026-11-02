const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/39X_safe_reference_union_abi" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/39X_safe_reference_union_abi", "input 'value' has an unsupported C ABI type", "failed without a diagnostic");
}
