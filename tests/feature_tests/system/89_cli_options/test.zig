const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/89_cli_options" {
    try expectSuccessfulBuild("tests/feature_tests/system/89_cli_options");
    try runExpect("tests/feature_tests/system/89_cli_options", 0);
}
