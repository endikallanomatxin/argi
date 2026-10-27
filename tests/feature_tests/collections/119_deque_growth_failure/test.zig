const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/119_deque_growth_failure" {
    try expectSuccessfulBuild("tests/feature_tests/collections/119_deque_growth_failure");
    try runExpect("tests/feature_tests/collections/119_deque_growth_failure", 0);
}
