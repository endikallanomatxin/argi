const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 98X_concurrent_aliased_wrapper_inputs" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/98X_concurrent_aliased_wrapper_inputs", "concurrent access conflicts through aliased function inputs");
}
