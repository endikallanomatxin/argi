const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/109X_checked_uninit_slot_read" {
    try buildExpectFail("tests/feature_tests/types/109X_checked_uninit_slot_read", "not dereferenceable");
}
