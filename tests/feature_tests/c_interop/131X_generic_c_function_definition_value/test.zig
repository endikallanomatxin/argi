const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "unspecialized C function cannot become a callback" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/131X_generic_c_function_definition_value", "function signature requires a fully specialized function definition", "failed without a diagnostic");
}
