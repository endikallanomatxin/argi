const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "429X_wrapped_slot_after_allocation_cleanup" {
    const path = "tests/feature_tests/types/429X_wrapped_slot_after_allocation_cleanup";
    try support.expectFrontendFailure(path, "reference depends on a root that has ended");
}
