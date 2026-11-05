const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 367_nested_associated_regions" {
    try support.expectSuccessfulBuild("tests/feature_tests/polymorphism/371_nested_associated_regions");
    try support.runExpect("tests/feature_tests/polymorphism/371_nested_associated_regions", 0);
}
