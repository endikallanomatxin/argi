const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/80_collection_contracts" {
    const path = "tests/feature_tests/collections/80_collection_contracts";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
