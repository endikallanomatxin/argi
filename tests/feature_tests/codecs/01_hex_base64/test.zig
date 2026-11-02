const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/codecs/01_hex_base64" {
    try expectSuccessfulBuild("tests/feature_tests/codecs/01_hex_base64");
    try runExpect("tests/feature_tests/codecs/01_hex_base64", 0);
}
