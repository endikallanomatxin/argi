const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/421X_reflection_private_fields" {
    try support.expectFrontendFailure("tests/feature_tests/types/421X_reflection_private_fields", "structural reflection cannot access private fields");
}
