const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/semver/01_parse_compare" {
    const path = "tests/feature_tests/semver/01_parse_compare";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
