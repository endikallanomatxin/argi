const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "propagation requires a fallible enclosing result" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/errors/138X_propagation_without_result", "error propagation requires an Errable function result", "failed without a diagnostic");
}
