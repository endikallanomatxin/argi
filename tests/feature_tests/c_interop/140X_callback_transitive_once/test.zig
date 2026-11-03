const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "callback cannot transitively invoke once" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/140X_callback_transitive_once", "callback may be invoked repeatedly and cannot consume a once function", "failed without a diagnostic");
}
