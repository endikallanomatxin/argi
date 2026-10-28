const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/47_deferred_flush" {
    try expectSuccessfulBuild("tests/feature_tests/io/47_deferred_flush");
    try runExpect("tests/feature_tests/io/47_deferred_flush", 0);
}
