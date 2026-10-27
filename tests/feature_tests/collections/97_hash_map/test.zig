const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/97_hash_map" {
    const path = "tests/feature_tests/collections/97_hash_map";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
