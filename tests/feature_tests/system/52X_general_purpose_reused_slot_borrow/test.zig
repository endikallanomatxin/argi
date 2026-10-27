const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/52X_general_purpose_reused_slot_borrow" {
    try buildExpectFail("tests/feature_tests/system/52X_general_purpose_reused_slot_borrow", "reference depends on a root that has ended");
}
