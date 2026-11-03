const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "signature query requires one function" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/96X_signature_query_arity", "function signature query requires exactly one function argument", "failed without a diagnostic");
}
