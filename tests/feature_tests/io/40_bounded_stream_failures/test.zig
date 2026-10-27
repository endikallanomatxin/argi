const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/40_bounded_stream_failures" {
    try expectSuccessfulBuild("tests/feature_tests/io/40_bounded_stream_failures");
    try runExpect("tests/feature_tests/io/40_bounded_stream_failures", 0);
}
