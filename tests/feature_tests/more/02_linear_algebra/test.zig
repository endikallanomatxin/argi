const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/more/02_linear_algebra" {
    const path = "tests/feature_tests/more/02_linear_algebra";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
