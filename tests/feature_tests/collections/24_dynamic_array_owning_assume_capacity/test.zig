const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/24_dynamic_array_owning_assume_capacity" {
    const test_path = "tests/feature_tests/collections/24_dynamic_array_owning_assume_capacity";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
