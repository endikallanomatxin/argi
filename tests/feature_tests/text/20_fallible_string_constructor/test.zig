const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/20_fallible_string_constructor" {
    const test_path = "tests/feature_tests/text/20_fallible_string_constructor";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
