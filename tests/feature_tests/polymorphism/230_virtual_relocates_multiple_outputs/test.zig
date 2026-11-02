const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/230_virtual_relocates_multiple_outputs" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/230_virtual_relocates_multiple_outputs");
    try runExpect("tests/feature_tests/polymorphism/230_virtual_relocates_multiple_outputs", 0);
}
