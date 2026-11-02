const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/62X_spatial_view_after_insert" {
    try expectFrontendFailure("tests/feature_tests/collections/62X_spatial_view_after_insert", "root that has ended");
}
