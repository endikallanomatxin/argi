const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "37X_generic_private_write" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/modules/37X_generic_private_write", "field '_hidden' is private to its module", "failed without a diagnostic");
}
