const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/273_internal_storage_nested_mapping" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/273_internal_storage_nested_mapping");
    try runExpect("tests/feature_tests/polymorphism/273_internal_storage_nested_mapping", 0);
}
