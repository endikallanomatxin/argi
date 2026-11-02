const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/83_string_hash_map_full_key" {
    const path = "tests/feature_tests/collections/83_string_hash_map_full_key";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
