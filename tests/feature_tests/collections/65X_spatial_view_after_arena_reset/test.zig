const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/65X_spatial_view_after_arena_reset" {
    try expectFrontendFailure("tests/feature_tests/collections/65X_spatial_view_after_arena_reset", "root that has ended");
}
