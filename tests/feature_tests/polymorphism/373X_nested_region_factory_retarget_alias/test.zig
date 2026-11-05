const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism/373X_nested_region_factory_retarget_alias" {
    try support.expectFrontendFailure("tests/feature_tests/polymorphism/373X_nested_region_factory_retarget_alias", "virtual capture observes storage");
}
