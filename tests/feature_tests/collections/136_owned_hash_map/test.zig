const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/136_owned_hash_map" {
    try expectSuccessfulBuild("tests/feature_tests/collections/136_owned_hash_map");
    try runExpect("tests/feature_tests/collections/136_owned_hash_map", 0);
}
