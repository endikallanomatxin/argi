const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/49_split_iteration" {
    try expectSuccessfulBuild("tests/feature_tests/text/49_split_iteration");
    try runExpect("tests/feature_tests/text/49_split_iteration", 0);
}
