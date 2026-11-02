const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/63X_spatial_view_after_remove" {
    try expectFrontendFailure("tests/feature_tests/collections/63X_spatial_view_after_remove", "root that has ended");
}
