const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 359X_region_empty_projection" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/359X_region_empty_projection", "region projections require at least one storage path");
}
