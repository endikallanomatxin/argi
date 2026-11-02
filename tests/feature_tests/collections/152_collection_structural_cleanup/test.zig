const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/152_collection_structural_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/collections/152_collection_structural_cleanup");
    try runExpect("tests/feature_tests/collections/152_collection_structural_cleanup", 0);
}
