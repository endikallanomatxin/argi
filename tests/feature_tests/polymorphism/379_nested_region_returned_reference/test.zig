const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "379_nested_region_returned_reference" {
    try support.expectSuccessfulBuild("tests/feature_tests/polymorphism/379_nested_region_returned_reference");
    try support.runExpect("tests/feature_tests/polymorphism/379_nested_region_returned_reference", 0);
}
