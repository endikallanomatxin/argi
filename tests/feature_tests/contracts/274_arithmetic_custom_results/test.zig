const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/274_arithmetic_custom_results" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/274_arithmetic_custom_results");
    try runExpect("tests/feature_tests/contracts/274_arithmetic_custom_results", 0);
}
