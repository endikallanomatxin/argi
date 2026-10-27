const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/34_utf8_scalars" {
    try expectSuccessfulBuild("tests/feature_tests/text/34_utf8_scalars");
    try runExpect("tests/feature_tests/text/34_utf8_scalars", 0);
}
