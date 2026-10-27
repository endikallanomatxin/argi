const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/84_errable_composition" {
    try expectSuccessfulBuild("tests/feature_tests/basics/84_errable_composition");
    try runExpect("tests/feature_tests/basics/84_errable_composition", 0);
}
