const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/35_utf8_invalid" {
    try expectSuccessfulBuild("tests/feature_tests/text/35_utf8_invalid");
    try runExpect("tests/feature_tests/text/35_utf8_invalid", 0);
}
