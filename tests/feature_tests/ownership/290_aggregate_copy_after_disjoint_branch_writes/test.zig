const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/290_aggregate_copy_after_disjoint_branch_writes" {
    const test_path = "tests/feature_tests/ownership/290_aggregate_copy_after_disjoint_branch_writes";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
