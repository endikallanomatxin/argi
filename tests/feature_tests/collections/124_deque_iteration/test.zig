const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/124_deque_iteration" {
    try expectSuccessfulBuild("tests/feature_tests/collections/124_deque_iteration");
    try runExpect("tests/feature_tests/collections/124_deque_iteration", 0);
}
