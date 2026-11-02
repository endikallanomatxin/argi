const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/errors/97_void_main_report_return" {
    try expectSuccessfulBuild("tests/feature_tests/errors/97_void_main_report_return");
    try runExpect("tests/feature_tests/errors/97_void_main_report_return", 0);
}
