const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/78X_spatial_forwarded_reference_after_set" {
    try expectFrontendFailure("tests/feature_tests/collections/78X_spatial_forwarded_reference_after_set", "root that has ended");
}
