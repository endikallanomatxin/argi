const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/327_ordered_comparison_evidence" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/327_ordered_comparison_evidence");
    try runExpect("tests/feature_tests/contracts/327_ordered_comparison_evidence", 0);
}
