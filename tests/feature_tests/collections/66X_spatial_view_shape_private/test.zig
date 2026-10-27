const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/66X_spatial_view_shape_private" {
    try expectFrontendFailure("tests/feature_tests/collections/66X_spatial_view_shape_private", "field '_shape' is private to its module");
}
