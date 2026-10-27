const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/io/41_bounded_stream_allocation_failure" {
    try expectSuccessfulBuild("tests/feature_tests/io/41_bounded_stream_allocation_failure");
    try runExpect("tests/feature_tests/io/41_bounded_stream_allocation_failure", 0);
}
