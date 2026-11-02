const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/75X_spatial_iterator_private_fields" {
    try expectFrontendFailure("tests/feature_tests/collections/75X_spatial_iterator_private_fields", "field '_index' is private");
}
