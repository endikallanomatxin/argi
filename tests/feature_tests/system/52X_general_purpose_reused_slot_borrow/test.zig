const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/52X_general_purpose_reused_slot_borrow" {
    try expectFrontendFailure("tests/feature_tests/system/52X_general_purpose_reused_slot_borrow", "reference depends on a root that has ended");
}
