const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/123_deque_zero_sized" {
    try expectSuccessfulBuild("tests/feature_tests/collections/123_deque_zero_sized");
    try runExpect("tests/feature_tests/collections/123_deque_zero_sized", 0);
}
