const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/177_hash_map_copy_vm" {
    const test_path = "tests/feature_tests/collections/177_hash_map_copy_vm";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
    try support.vmExpect(test_path, 0, null);
}
