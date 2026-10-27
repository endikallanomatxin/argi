const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/117_deque" {
    try expectSuccessfulBuild("tests/feature_tests/collections/117_deque");
    try runExpect("tests/feature_tests/collections/117_deque", 0);
}
