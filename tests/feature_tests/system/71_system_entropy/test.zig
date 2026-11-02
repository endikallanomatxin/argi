const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/71_system_entropy" {
    const path = "tests/feature_tests/system/71_system_entropy";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
