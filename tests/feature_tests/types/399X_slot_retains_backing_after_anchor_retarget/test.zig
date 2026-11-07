const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/399X_slot_retains_backing_after_anchor_retarget" {
    try support.expectFrontendFailure("tests/feature_tests/types/399X_slot_retains_backing_after_anchor_retarget", "reference depends on a root that has ended");
}
