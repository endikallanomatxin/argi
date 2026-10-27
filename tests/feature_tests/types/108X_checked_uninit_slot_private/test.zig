const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/108X_checked_uninit_slot_private" {
    try expectFrontendFailure("tests/feature_tests/types/108X_checked_uninit_slot_private", "field '_raw' is private to its module");
}
