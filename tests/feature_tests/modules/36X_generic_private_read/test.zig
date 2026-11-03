const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "36X_generic_private_read" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/modules/36X_generic_private_read", "field '_hidden' is private to its module", "failed without a diagnostic");
}
