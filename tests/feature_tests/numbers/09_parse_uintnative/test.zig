const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/09_parse_uintnative" {
    try expectSuccessfulBuild("tests/feature_tests/numbers/09_parse_uintnative");
    try runExpect("tests/feature_tests/numbers/09_parse_uintnative", 0);
}
