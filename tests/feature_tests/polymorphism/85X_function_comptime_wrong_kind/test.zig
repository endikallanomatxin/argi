const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "function compile-time argument rejects a type family" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/85X_function_comptime_wrong_kind", "compile-time argument must be a function definition", "failed without a diagnostic");
}
