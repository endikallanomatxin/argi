const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/51_virtual_associated_parameters" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/51_virtual_associated_parameters");
    try runExpect("tests/feature_tests/polymorphism/51_virtual_associated_parameters", 0);
}
