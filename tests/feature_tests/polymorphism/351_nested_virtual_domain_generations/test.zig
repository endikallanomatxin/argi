const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 351_nested_virtual_domain_generations" {
    try support.expectSuccessfulBuild("tests/feature_tests/polymorphism/351_nested_virtual_domain_generations");
    try support.runExpect("tests/feature_tests/polymorphism/351_nested_virtual_domain_generations", 0);
}
