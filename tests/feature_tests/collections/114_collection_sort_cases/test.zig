const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/114_collection_sort_cases" {
    const path = "tests/feature_tests/collections/114_collection_sort_cases";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
