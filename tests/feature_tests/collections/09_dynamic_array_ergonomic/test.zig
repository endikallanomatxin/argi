const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/09_dynamic_array_ergonomic" {
    const test_path = "tests/feature_tests/collections/09_dynamic_array_ergonomic";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 80);
}
