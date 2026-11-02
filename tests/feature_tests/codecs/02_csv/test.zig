const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/codecs/02_csv" {
    try expectSuccessfulBuild("tests/feature_tests/codecs/02_csv");
    try runExpect("tests/feature_tests/codecs/02_csv", 0);
}
