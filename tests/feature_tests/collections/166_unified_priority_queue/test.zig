const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/166_unified_priority_queue" {
    try expectSuccessfulBuild("tests/feature_tests/collections/166_unified_priority_queue");
    try runExpect("tests/feature_tests/collections/166_unified_priority_queue", 0);
}
