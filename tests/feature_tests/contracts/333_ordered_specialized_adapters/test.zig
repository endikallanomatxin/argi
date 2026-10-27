const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/333_ordered_specialized_adapters" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/333_ordered_specialized_adapters");
    try runExpect("tests/feature_tests/contracts/333_ordered_specialized_adapters", 0);
}
