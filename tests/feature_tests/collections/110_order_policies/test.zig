const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/110_order_policies" {
    const path = "tests/feature_tests/collections/110_order_policies";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
