const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 96X_concurrent_aliased_helper_inputs" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/96X_concurrent_aliased_helper_inputs", "concurrent access conflicts through aliased function inputs");
}
