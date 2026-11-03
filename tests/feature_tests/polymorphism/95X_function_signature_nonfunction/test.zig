const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "function signature query rejects a type" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/95X_function_signature_nonfunction", "function signature requires a function definition", "failed without a diagnostic");
}
