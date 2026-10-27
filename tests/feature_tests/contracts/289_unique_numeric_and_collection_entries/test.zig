const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/289_unique_numeric_and_collection_entries" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/289_unique_numeric_and_collection_entries");
    try runExpect("tests/feature_tests/contracts/289_unique_numeric_and_collection_entries", 0);
}
