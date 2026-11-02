const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/274_virtual_internal_storage_layouts" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/274_virtual_internal_storage_layouts");
    try runExpect("tests/feature_tests/polymorphism/274_virtual_internal_storage_layouts", 0);
}
