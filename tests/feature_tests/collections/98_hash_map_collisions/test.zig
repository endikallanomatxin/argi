const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/98_hash_map_collisions" {
    const path = "tests/feature_tests/collections/98_hash_map_collisions";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
