const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/32_generic_view_dispatch_order" {
    const path = "tests/feature_tests/functions/32_generic_view_dispatch_order";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
