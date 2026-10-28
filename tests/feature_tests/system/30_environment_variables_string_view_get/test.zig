const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/30_environment_variables_string_view_get" {
    const test_path = "tests/feature_tests/system/30_environment_variables_string_view_get";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
