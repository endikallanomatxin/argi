const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 363X_region_initializer_value" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/363X_region_initializer_value", "associated region requires a region(self.path) projection initializer");
}
