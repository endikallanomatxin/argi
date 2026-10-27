const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/96_hash_policies" {
    const path = "tests/feature_tests/collections/96_hash_policies";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
