const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "isolated callback rejects transitive global reference" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/141X_isolated_callback_global_reference", "isolated callback cannot access nonplain global storage", "failed without a diagnostic");
}
