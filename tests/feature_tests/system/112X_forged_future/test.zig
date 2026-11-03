const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "native future receipts cannot be fabricated" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/system/112X_forged_future", "private", "failed without a diagnostic");
}
