const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/34_dynamic_array_string_copy" {
    const test_path = "tests/feature_tests/collections/34_dynamic_array_string_copy";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
