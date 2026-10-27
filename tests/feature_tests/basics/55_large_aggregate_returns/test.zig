const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/55_large_aggregate_returns" {
    const path = "tests/feature_tests/basics/55_large_aggregate_returns";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
