const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "reflection rejects an unspecialized function" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/92X_unspecialized_function_reflection", "function signature requires a fully specialized function definition", "failed without a diagnostic");
}
