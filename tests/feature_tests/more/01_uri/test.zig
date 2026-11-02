const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/more/01_uri" {
    const path = "tests/feature_tests/more/01_uri";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
