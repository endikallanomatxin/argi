const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/88_path_normalization" {
    try expectSuccessfulBuild("tests/feature_tests/system/88_path_normalization");
    try runExpect("tests/feature_tests/system/88_path_normalization", 0);
}
