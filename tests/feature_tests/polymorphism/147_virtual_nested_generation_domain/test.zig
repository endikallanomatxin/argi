const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/147_virtual_nested_generation_domain" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/147_virtual_nested_generation_domain");
    try runExpect("tests/feature_tests/polymorphism/147_virtual_nested_generation_domain", 0);
}
