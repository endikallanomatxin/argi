const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/140_virtual_nested_generation" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/140_virtual_nested_generation");
    try runExpect("tests/feature_tests/polymorphism/140_virtual_nested_generation", 0);
}
