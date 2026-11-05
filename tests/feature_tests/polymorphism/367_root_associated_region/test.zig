const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 367_root_associated_region" {
    try support.expectSuccessfulBuild("tests/feature_tests/polymorphism/367_root_associated_region");
    try support.runExpect("tests/feature_tests/polymorphism/367_root_associated_region", 0);
}
