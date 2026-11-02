const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/106_report_return_block" {
    try expectSuccessfulBuild("tests/feature_tests/errors/106_report_return_block");
    try runExpect("tests/feature_tests/errors/106_report_return_block", 0);
}
