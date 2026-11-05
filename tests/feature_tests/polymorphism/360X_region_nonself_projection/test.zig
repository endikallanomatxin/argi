const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 360X_region_nonself_projection" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/360X_region_nonself_projection", "region projections must select fields from symbolic self");
}
