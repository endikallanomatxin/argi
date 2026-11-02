const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/210_virtual_nested_consumption_inherited" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/210_virtual_nested_consumption_inherited");
    try runExpect("tests/feature_tests/polymorphism/210_virtual_nested_consumption_inherited", 0);
}
