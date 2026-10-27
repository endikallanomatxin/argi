const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/39_bounded_streams" {
    try expectSuccessfulBuild("tests/feature_tests/io/39_bounded_streams");
    try runExpect("tests/feature_tests/io/39_bounded_streams", 0);
}
