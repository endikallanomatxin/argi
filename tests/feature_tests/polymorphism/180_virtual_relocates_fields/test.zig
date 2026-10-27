const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/180_virtual_relocates_fields" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/180_virtual_relocates_fields");
    try runExpect("tests/feature_tests/polymorphism/180_virtual_relocates_fields", 0);
}
