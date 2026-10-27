const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/91_cli_schema" {
    try expectSuccessfulBuild("tests/feature_tests/system/91_cli_schema");
    try runExpect("tests/feature_tests/system/91_cli_schema", 0);
}
