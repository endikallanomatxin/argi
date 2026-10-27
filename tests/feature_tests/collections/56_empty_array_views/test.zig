const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/56_empty_array_views" {
    const path = "tests/feature_tests/collections/56_empty_array_views";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
