const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/397X_slot_retains_backing_with_unrelated_anchor" {
    try support.expectFrontendFailure("tests/feature_tests/types/397X_slot_retains_backing_with_unrelated_anchor", "reference depends on a root that has ended");
}
