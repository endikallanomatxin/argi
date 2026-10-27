const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/35_string_replace" {
    const path = "tests/feature_tests/text/35_string_replace";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
