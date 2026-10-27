const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/58_spatial_borrowed_ranges" {
    const path = "tests/feature_tests/collections/58_spatial_borrowed_ranges";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
