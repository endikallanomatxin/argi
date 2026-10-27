const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/183_virtual_relocates_allocation" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/183_virtual_relocates_allocation");
    try runExpect("tests/feature_tests/polymorphism/183_virtual_relocates_allocation", 0);
}
