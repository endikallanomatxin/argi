const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/14_string_concat_string_view" {
    const test_path = "tests/feature_tests/text/14_string_concat_string_view";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
