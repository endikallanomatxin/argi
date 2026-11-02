const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/113_collection_sort" {
    const path = "tests/feature_tests/collections/113_collection_sort";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
