const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/18_string_view_equals_string" {
    const test_path = "tests/feature_tests/text/18_string_view_equals_string";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
