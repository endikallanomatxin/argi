const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 95X_projected_global_alias_not_bounded" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/95X_projected_global_alias_not_bounded", "cannot prove access bounds: implementation has unknown or global memory effects");
}
