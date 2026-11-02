const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/35_dynamic_array_fallible_copy_cleanup" {
    const test_path = "tests/feature_tests/collections/35_dynamic_array_fallible_copy_cleanup";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
