const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/27_dynamic_array_owning_pop_preserves_rest" {
    const test_path = "tests/feature_tests/collections/27_dynamic_array_owning_pop_preserves_rest";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
