const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/27_assume_automatic_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/functions/27_assume_automatic_cleanup");
    try runExpect("tests/feature_tests/functions/27_assume_automatic_cleanup", 0);
}
