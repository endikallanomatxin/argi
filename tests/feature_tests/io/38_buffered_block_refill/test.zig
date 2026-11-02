const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/38_buffered_block_refill" {
    try expectSuccessfulBuild("tests/feature_tests/io/38_buffered_block_refill");
    try runExpect("tests/feature_tests/io/38_buffered_block_refill", 0);
}
