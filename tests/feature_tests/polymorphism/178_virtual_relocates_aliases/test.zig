const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/178_virtual_relocates_aliases" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/178_virtual_relocates_aliases");
    try runExpect("tests/feature_tests/polymorphism/178_virtual_relocates_aliases", 0);
}
