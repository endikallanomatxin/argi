const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/43_limited_reader" {
    try expectSuccessfulBuild("tests/feature_tests/io/43_limited_reader");
    try runExpect("tests/feature_tests/io/43_limited_reader", 0);
}
