const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/108X_checked_uninit_slot_private" {
    try buildExpectFail("tests/feature_tests/types/108X_checked_uninit_slot_private", "field '_raw' is private to its module");
}
