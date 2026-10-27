const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/150_dynamic_array_geometric_growth" {
    try expectSuccessfulBuild("tests/feature_tests/collections/150_dynamic_array_geometric_growth");
    try runExpect("tests/feature_tests/collections/150_dynamic_array_geometric_growth", 0);
}
