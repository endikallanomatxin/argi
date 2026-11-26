const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/180_independent_array_growth_after_return" {
    try expectSuccessfulBuild("tests/feature_tests/collections/180_independent_array_growth_after_return");
    try runExpect("tests/feature_tests/collections/180_independent_array_growth_after_return", 0);
}
