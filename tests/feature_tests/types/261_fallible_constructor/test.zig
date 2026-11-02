const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/261_fallible_constructor" {
    const test_path = "tests/feature_tests/types/261_fallible_constructor";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
