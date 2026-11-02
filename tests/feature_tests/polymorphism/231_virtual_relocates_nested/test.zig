const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/231_virtual_relocates_nested" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/231_virtual_relocates_nested");
    try runExpect("tests/feature_tests/polymorphism/231_virtual_relocates_nested", 0);
}
