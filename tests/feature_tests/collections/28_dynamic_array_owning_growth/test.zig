const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/28_dynamic_array_owning_growth" {
    const test_path = "tests/feature_tests/collections/28_dynamic_array_owning_growth";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
