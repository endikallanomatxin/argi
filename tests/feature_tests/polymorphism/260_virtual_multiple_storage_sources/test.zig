const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/260_virtual_multiple_storage_sources" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/260_virtual_multiple_storage_sources");
    try runExpect("tests/feature_tests/polymorphism/260_virtual_multiple_storage_sources", 0);
}
