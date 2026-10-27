const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/112X_checked_uninit_slot_backing_reset" {
    try expectFrontendFailure("tests/feature_tests/types/112X_checked_uninit_slot_backing_reset", "root that has ended");
}
