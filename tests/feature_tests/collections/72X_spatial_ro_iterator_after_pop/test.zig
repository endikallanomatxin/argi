const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/72X_spatial_ro_iterator_after_pop" {
    try expectFrontendFailure("tests/feature_tests/collections/72X_spatial_ro_iterator_after_pop", "root that has ended");
}
