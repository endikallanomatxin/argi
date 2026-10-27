const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/235_virtual_relocates_forwarded_output" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/235_virtual_relocates_forwarded_output");
    try runExpect("tests/feature_tests/polymorphism/235_virtual_relocates_forwarded_output", 0);
}
