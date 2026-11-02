const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/118_deque_ownership" {
    try expectSuccessfulBuild("tests/feature_tests/collections/118_deque_ownership");
    try runExpect("tests/feature_tests/collections/118_deque_ownership", 0);
}
