const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/21_once_completed_defaults" {
    try expectSuccessfulBuild("tests/feature_tests/system/21_once_completed_defaults");
    try runExpect("tests/feature_tests/system/21_once_completed_defaults", 42);
    try vmExpect("tests/feature_tests/system/21_once_completed_defaults", 42, null);
}
