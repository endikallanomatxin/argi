const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/400X_wrapped_slot_retains_backing" {
    try support.expectFrontendFailure("tests/feature_tests/types/400X_wrapped_slot_retains_backing", "reference depends on a root that has ended");
}
