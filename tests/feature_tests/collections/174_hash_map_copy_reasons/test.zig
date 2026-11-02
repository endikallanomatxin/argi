const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/174_hash_map_copy_reasons" {
    const test_path = "tests/feature_tests/collections/174_hash_map_copy_reasons";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
