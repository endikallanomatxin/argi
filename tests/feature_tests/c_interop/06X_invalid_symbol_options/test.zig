const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/06X_invalid_symbol_options" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/06X_invalid_symbol_options", "CFunction '.symbol' requires a string literal", "failed without a diagnostic");
}
