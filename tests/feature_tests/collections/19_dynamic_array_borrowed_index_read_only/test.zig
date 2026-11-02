const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/19_dynamic_array_borrowed_index_read_only" {
    const test_path = "tests/feature_tests/collections/19_dynamic_array_borrowed_index_read_only";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
