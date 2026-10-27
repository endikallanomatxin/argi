const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/243_relocates_forwarded_output_repackaged" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/243_relocates_forwarded_output_repackaged");
    try runExpect("tests/feature_tests/polymorphism/243_relocates_forwarded_output_repackaged", 0);
}
