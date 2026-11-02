const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/109X_checked_uninit_slot_read" {
    try expectFrontendFailure("tests/feature_tests/types/109X_checked_uninit_slot_read", "not dereferenceable");
}
