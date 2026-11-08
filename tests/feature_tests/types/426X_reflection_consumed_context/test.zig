const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/426X_reflection_consumed_context" {
    try support.expectFrontendFailure("tests/feature_tests/types/426X_reflection_consumed_context", "structural reflection context must be implicitly copyable");
}
