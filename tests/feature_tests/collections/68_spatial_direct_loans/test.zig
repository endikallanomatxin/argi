const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/68_spatial_direct_loans" {
    const test_path = "tests/feature_tests/collections/68_spatial_direct_loans";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
