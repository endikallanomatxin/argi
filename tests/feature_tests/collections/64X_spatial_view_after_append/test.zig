const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/64X_spatial_view_after_append" {
    try expectFrontendFailure("tests/feature_tests/collections/64X_spatial_view_after_append", "root that has ended");
}
