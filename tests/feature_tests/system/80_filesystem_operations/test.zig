const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/80_filesystem_operations" {
    try expectSuccessfulBuild("tests/feature_tests/system/80_filesystem_operations");
    try runExpect("tests/feature_tests/system/80_filesystem_operations", 0);
}
