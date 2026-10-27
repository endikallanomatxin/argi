const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/45_ascii_foundations" {
    try expectSuccessfulBuild("tests/feature_tests/text/45_ascii_foundations");
    try runExpect("tests/feature_tests/text/45_ascii_foundations", 0);
}
