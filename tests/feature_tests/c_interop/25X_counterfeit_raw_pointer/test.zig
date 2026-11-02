const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/25X_counterfeit_raw_pointer" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/25X_counterfeit_raw_pointer", "input 'pointer' has an unsupported C ABI type", "failed without a diagnostic");
}
