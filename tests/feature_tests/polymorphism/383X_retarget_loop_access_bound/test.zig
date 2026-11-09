const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism/383X_retarget_loop_access_bound" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/383X_retarget_loop_access_bound", "cannot prove access bounds: implementation has unknown or global memory effects");
}
