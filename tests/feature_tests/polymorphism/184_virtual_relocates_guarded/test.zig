const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/184_virtual_relocates_guarded" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/184_virtual_relocates_guarded");
    try runExpect("tests/feature_tests/polymorphism/184_virtual_relocates_guarded", 0);
}
