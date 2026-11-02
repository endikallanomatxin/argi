const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/133_opaque_local_aggregate_wrapper_allows_unrelated_end" {
    const test_path = "tests/feature_tests/ownership/133_opaque_local_aggregate_wrapper_allows_unrelated_end";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
