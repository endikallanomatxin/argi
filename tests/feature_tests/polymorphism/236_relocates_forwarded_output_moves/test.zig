const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/236_relocates_forwarded_output_moves" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/236_relocates_forwarded_output_moves");
    try runExpect("tests/feature_tests/polymorphism/236_relocates_forwarded_output_moves", 0);
}
