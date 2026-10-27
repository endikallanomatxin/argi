const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/25_integer_parsing" {
    const path = "tests/feature_tests/text/25_integer_parsing";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
