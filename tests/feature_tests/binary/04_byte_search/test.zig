const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/binary/04_byte_search" {
    try expectSuccessfulBuild("tests/feature_tests/binary/04_byte_search");
    try runExpect("tests/feature_tests/binary/04_byte_search", 0);
}
