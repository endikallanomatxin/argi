const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 85X_latent_cleanup_not_no_access" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/85X_latent_cleanup_not_no_access", "cannot prove access bounds: implementation has unknown or global memory effects");
}
