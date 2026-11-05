const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism/374_nested_region_factory_disjoint_update" {
    try support.expectSuccessfulBuild("tests/feature_tests/polymorphism/374_nested_region_factory_disjoint_update");
    try support.runExpect("tests/feature_tests/polymorphism/374_nested_region_factory_disjoint_update", 0);
}
