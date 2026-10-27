const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/115_collection_sort_records" {
    const path = "tests/feature_tests/collections/115_collection_sort_records";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
