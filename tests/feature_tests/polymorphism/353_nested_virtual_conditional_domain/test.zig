const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "polymorphism 353_nested_virtual_conditional_domain" {
    try support.expectSuccessfulBuild("tests/feature_tests/polymorphism/353_nested_virtual_conditional_domain");
    try support.runExpect("tests/feature_tests/polymorphism/353_nested_virtual_conditional_domain", 0);
}
