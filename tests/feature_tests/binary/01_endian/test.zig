const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/binary/01_endian" {
    try expectSuccessfulBuild("tests/feature_tests/binary/01_endian");
    try runExpect("tests/feature_tests/binary/01_endian", 0);
}
