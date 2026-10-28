const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/48_line_error_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/io/48_line_error_cleanup");
    try runExpect("tests/feature_tests/io/48_line_error_cleanup", 0);
}
