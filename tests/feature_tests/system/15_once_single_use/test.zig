const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/15_once_single_use" {
    const test_path = "tests/feature_tests/system/15_once_single_use";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
    try vmExpect("tests/feature_tests/system/15_once_single_use", 0, null);
}
