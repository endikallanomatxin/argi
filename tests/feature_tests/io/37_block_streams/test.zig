const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/37_block_streams" {
    try expectSuccessfulBuild("tests/feature_tests/io/37_block_streams");
    try runExpect("tests/feature_tests/io/37_block_streams", 0);
}
