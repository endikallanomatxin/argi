const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 368X_root_region_overlaps_field" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/368X_root_region_overlaps_field", "overlap");
}
