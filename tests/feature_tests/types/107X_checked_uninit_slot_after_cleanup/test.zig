const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/107X_checked_uninit_slot_after_cleanup" {
    try buildExpectFail("tests/feature_tests/types/107X_checked_uninit_slot_after_cleanup", "root that has ended");
}
