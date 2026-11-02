const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/40X_dynamic_array_set_empty" {
    const test_path = "tests/feature_tests/collections/40X_dynamic_array_set_empty";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
