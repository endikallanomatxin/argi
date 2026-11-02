const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/105_hash_set" {
    const path = "tests/feature_tests/collections/105_hash_set";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
