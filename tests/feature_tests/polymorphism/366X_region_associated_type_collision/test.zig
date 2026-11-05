const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 366X_region_associated_type_collision" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/366X_region_associated_type_collision", "contract regions and associated elements require distinct names");
}
