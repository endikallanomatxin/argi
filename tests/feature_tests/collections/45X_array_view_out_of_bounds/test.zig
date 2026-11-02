const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/45X_array_view_out_of_bounds" {
    const test_path = "tests/feature_tests/collections/45X_array_view_out_of_bounds";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
