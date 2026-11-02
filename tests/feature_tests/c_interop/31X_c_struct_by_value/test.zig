const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/31X_c_struct_by_value" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/31X_c_struct_by_value", "input 'record' has an unsupported C ABI type", "failed without a diagnostic");
}
