const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/150X_bit_set_view_after_cleanup" {
    try expectFrontendFailure("tests/feature_tests/collections/150X_bit_set_view_after_cleanup", "root that has ended");
}
