const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 355_associated_region_members" {
    try support.expectSuccessfulBuild("tests/feature_tests/polymorphism/355_associated_region_members");
    try support.runExpect("tests/feature_tests/polymorphism/355_associated_region_members", 0);
}
