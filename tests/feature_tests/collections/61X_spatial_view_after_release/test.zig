const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/61X_spatial_view_after_release" {
    try expectFrontendFailure("tests/feature_tests/collections/61X_spatial_view_after_release", "root that has ended");
}
