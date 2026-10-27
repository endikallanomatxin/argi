const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/semver/02_format" {
    const path = "tests/feature_tests/semver/02_format";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
