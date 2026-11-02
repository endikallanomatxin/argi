const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/106_hash_set_growth_failure" {
    const path = "tests/feature_tests/collections/106_hash_set_growth_failure";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
