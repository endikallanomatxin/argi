const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/93_directory_walk" {
    try expectSuccessfulBuild("tests/feature_tests/system/93_directory_walk");
    try runExpect("tests/feature_tests/system/93_directory_walk", 0);
}
