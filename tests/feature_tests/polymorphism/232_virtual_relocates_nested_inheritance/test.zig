const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/232_virtual_relocates_nested_inheritance" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/232_virtual_relocates_nested_inheritance");
    try runExpect("tests/feature_tests/polymorphism/232_virtual_relocates_nested_inheritance", 0);
}
