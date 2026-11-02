const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/137_owned_hash_lifecycle" {
    try expectSuccessfulBuild("tests/feature_tests/collections/137_owned_hash_lifecycle");
    try runExpect("tests/feature_tests/collections/137_owned_hash_lifecycle", 0);
}
