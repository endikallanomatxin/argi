const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/30X_c_struct_non_c_field" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/30X_c_struct_non_c_field", "field 'ordinary' has no supported C representation", "failed without a diagnostic");
}
