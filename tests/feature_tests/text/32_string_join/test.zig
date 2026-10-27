const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/32_string_join" {
    const path = "tests/feature_tests/text/32_string_join";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
