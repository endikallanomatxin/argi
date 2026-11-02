const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/binary/02_cursor" {
    try expectSuccessfulBuild("tests/feature_tests/binary/02_cursor");
    try runExpect("tests/feature_tests/binary/02_cursor", 0);
}
