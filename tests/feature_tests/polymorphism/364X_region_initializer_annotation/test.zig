const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 364X_region_initializer_annotation" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/364X_region_initializer_annotation", "region members use");
}
