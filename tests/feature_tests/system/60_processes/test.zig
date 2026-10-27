const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/60_processes" {
    const path = "tests/feature_tests/system/60_processes";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
