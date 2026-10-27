const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/21_write_from_array_view" {
    const test_path = "tests/feature_tests/io/21_write_from_array_view";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
