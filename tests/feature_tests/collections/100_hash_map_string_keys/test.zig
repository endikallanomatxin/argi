const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/100_hash_map_string_keys" {
    const path = "tests/feature_tests/collections/100_hash_map_string_keys";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
